module.exports = {
    httpAdminRoot: '/admin',
    httpNodeRoot: '/',
    uiPort: 1880,
    userDir: '/home/plantomioX1/.node-red',
    // adminAuth: {
    //      type: "credentials",
    //      users: [{
    //          username: "",
    //          password: "",
    //          permissions: "*"
    //      }]
    //  },
    functionGlobalContext: {
        // Make project configuration available to functions
        config: {
            projectName: "plantomio",
            mqtt: {
                host: "localhost",
                port: 1883,
                username: "plantomioX1",
                password: "plantomioX1Pass"
            },
            vm: {
                host: "localhost",
                port: 8428
            }
        }
    },
    httpNodeCors: {
        origin: "*",
        methods: "GET,PUT,POST,DELETE"
    },
    editorTheme: { 
        projects: { enabled: false }
    }
};

