module.exports = {
    httpAdminRoot: '/admin',
    httpNodeRoot: '/',
    userDir: '__BASE_DIR__/.node-red',
    adminAuth: {
        type: "credentials",
        users: [{
            username: "__NODE_RED_USERNAME__",
            password: "__NODE_RED_PASSWORD_HASH__",
            permissions: "*"
        }]
    },
    editorTheme: { projects: { enabled: false } }
}