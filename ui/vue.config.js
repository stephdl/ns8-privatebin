module.exports = {
  css: {
    loaderOptions: {
      sass: {
        sassOptions: {
          silenceDeprecations: ["import", "global-builtin", "color-functions", "if-function", "legacy-js-api"],
        },
      },
    },
  },
  publicPath: "./",
  chainWebpack: (config) => {
    // The core reads the app logo from img/: never inline it as base64
    config.module
      .rule("images")
      .use("url-loader")
      .tap((options) => ({ ...options, limit: -1 }));
  },
  configureWebpack: {
    optimization: {
      splitChunks: {
        maxSize: 500000,
      },
    },
  },
};
