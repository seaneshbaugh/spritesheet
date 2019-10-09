const webpack = require("webpack");
const merge = require("webpack-merge");
const MiniCssExtractPlugin = require("mini-css-extract-plugin");

const env = process.env.NODE_ENV || "development";
const production = env == "production";

const node_modules_dir = "/assets/node_modules";

const plugins = [
  new MiniCssExtractPlugin({
    filename: "[name].css",
    chunkFilename: "[id].css",
    ignoreOrder: false
  })
];

if (production) {
  plugins.push(
    new webpack.optimize.UglifyJsPlugin({
      compress: { warnings: false },
      output: { comments: false }
    })
  );
} else {
  plugins.push(
    new webpack.EvalSourceMapDevToolPlugin()
  );
}

const common = {
  watchOptions: {
    poll: true
  },
  module: {
    rules: [
      {
        test: /\.jsx?$/,
        exclude: [node_modules_dir],
        use: {
          loader: "babel-loader",
          options: {
            presets: ["@babel/preset-env", "@babel/preset-react"]
          }
        }
      },
      {
        test: /\.s[ac]ss$/,
        use: [
          (production ? {
            loader: MiniCssExtractPlugin.loader,
            options: {
              publicPath: "../public",
              hmr: !production
            }
          } : 'style-loader'),
          "css-loader",
          "sass-loader"
        ]
      },
      {
        test: /\.(png|jpe?g|gif|svg)$/,
        use: [
          {
            loader: "file-loader",
            options: {
              name: "images/[name].[ext]?[contenthash]"
            }
          }
        ]
      },
      {
        test: /\.(ttf|otf|eot|svg|woff2?)$/,
        use: [
          {
            loader: "file-loader",
            options: {
              name: "fonts/[name].[ext]?[contenthash]"
            }
          }
        ]
      }
    ]
  },
  plugins: plugins
};

module.exports = [
  merge(common, {
    entry: [
      __dirname + "/app/app.scss",
      __dirname + "/app/app.js",
    ],
    output: {
      path: __dirname + "/../public",
      filename: "js/app.js"
    },
    resolve: {
      modules: [
        node_modules_dir,
        __dirname + "/app"
      ]
    }
  })
];
