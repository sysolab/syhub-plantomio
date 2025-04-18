// Plantomio Service Worker
const CACHE_NAME = 'plantomio-cache-v1';
const urlsToCache = [
  '/',
  '/static/css/styles.css',
  '/static/js/main.js',
  '/static/images/icon-192.png',
  '/static/images/icon-512.png'
];

// Install event - cache essential files
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => {
        console.log('Opened cache');
        return cache.addAll(urlsToCache);
      })
  );
});

// Activate event - clean up old caches
self.addEventListener('activate', event => {
  const cacheWhitelist = [CACHE_NAME];
  event.waitUntil(
    caches.keys().then(cacheNames => {
      return Promise.all(
        cacheNames.map(cacheName => {
          if (cacheWhitelist.indexOf(cacheName) === -1) {
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
});

// Fetch event - serve from cache, fall back to network
self.addEventListener('fetch', event => {
  // For API requests, try network first, then cache
  if (event.request.url.includes('/api/') || event.request.url.includes('/data/')) {
    event.respondWith(
      fetch(event.request)
        .then(response => {
          // Clone the response since we'll use it twice
          const responseToCache = response.clone();
          
          // Only cache successful responses
          if (response.status === 200) {
            caches.open(CACHE_NAME)
              .then(cache => {
                // Store with a 5-minute expiration
                const headers = new Headers(responseToCache.headers);
                headers.append('sw-fetched-on', new Date().getTime());
                
                // Create a new response with added headers
                const responseWithTimestamp = new Response(
                  responseToCache.body, 
                  {
                    status: responseToCache.status,
                    statusText: responseToCache.statusText,
                    headers: headers
                  }
                );
                
                // Store in cache
                cache.put(event.request, responseWithTimestamp);
              });
          }
          
          return response;
        })
        .catch(err => {
          // If network fails, try the cache
          return caches.match(event.request)
            .then(cachedResponse => {
              if (cachedResponse) {
                // Check if cached response is too old (over 5 minutes)
                const fetchedOn = cachedResponse.headers.get('sw-fetched-on');
                if (fetchedOn) {
                  const fetchedTime = parseInt(fetchedOn, 10);
                  const now = new Date().getTime();
                  
                  // Return cached response if less than 5 minutes old
                  if (now - fetchedTime < 5 * 60 * 1000) {
                    return cachedResponse;
                  }
                } else {
                  // No timestamp, return it anyway
                  return cachedResponse;
                }
              }
              
              // If no cached response, return empty data with offline notification
              if (event.request.headers.get('accept').includes('application/json')) {
                return new Response(JSON.stringify({
                  offline: true,
                  message: 'You are offline. This data may be outdated.'
                }), {
                  headers: { 'Content-Type': 'application/json' }
                });
              }
              
              // For non-JSON requests, return generic offline message
              return caches.match('/offline.html');
            });
        })
    );
  } else {
    // For other requests (static assets), try cache first, then network
    event.respondWith(
      caches.match(event.request)
        .then(response => {
          if (response) {
            return response;
          }
          
          // Clone the request since we'll use it twice
          const fetchRequest = event.request.clone();
          
          return fetch(fetchRequest).then(response => {
            // Check if we received a valid response
            if (!response || response.status !== 200 || response.type !== 'basic') {
              return response;
            }
            
            // Clone the response since we'll use it twice
            const responseToCache = response.clone();
            
            // Cache this response for future
            caches.open(CACHE_NAME)
              .then(cache => {
                cache.put(event.request, responseToCache);
              });
            
            return response;
          });
        })
    );
  }
});

// Background sync for offline data submission
self.addEventListener('sync', event => {
  if (event.tag === 'sync-sensor-data') {
    event.waitUntil(
      // Process any pending sensor data
      self.clients.matchAll().then(clients => {
        clients.forEach(client => {
          client.postMessage({
            type: 'BACKGROUND_SYNC',
            message: 'Syncing data in background'
          });
        });
      })
    );
  }
});