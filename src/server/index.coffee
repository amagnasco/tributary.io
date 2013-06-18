http = require 'http'
express = require 'express'
coffeeify = require 'coffeeify'
gzippo = require 'gzippo'
derby = require 'derby'

racerBrowserChannel = require 'racer-browserchannel'
liveDbMongo = require 'livedb-mongo'


app = require '../app'
serverError = require './serverError'

expressApp = express()
server = http.createServer(expressApp)

module.exports = server

# The store creates models and syncs data
if process.env.OPENREDIS_URL
  redisUrl = require('url').parse process.env.OPENREDIS_URL
  redis = require('redis').createClient redisUrl.port, redisUrl.hostname
  redis.auth(redisUrl.auth.split(":")[1])
else
  redis = require('redis').createClient()
redis.select 4

mongoUri = process.env.MONGOHQ_URL || 'mongodb://localhost:27017/tributary-io'
store = derby.createStore
  db: liveDbMongo(mongoUri + '?auto_reconnect', safe: true)
  redis: redis


ONE_YEAR = 1000 * 60 * 60 * 24 * 365
mount = '/inlet'
publicDir = require('path').join __dirname + '/../../public'


store.on 'bundle', (browserify) ->
  browserify.add publicDir + '/js/jquery-1.9.1.min.js'
  GLOBAL.CodeMirror = {}
  browserify.add publicDir + '/js/3rdparty.js'
  # Add support for directly requiring coffeescript in browserify bundles
  browserify.transform coffeeify

ipMiddleware = (req, res, next) ->
  forwarded = req.header 'x-forwarded-for'
  ipAddress = forwarded && forwarded.split(',')[0] ||
    req.connection.remoteAddress

  model = req.getModel()
  model.set '_info.ipAddress', ipAddress
  next()

expressApp
  .use(express.favicon())

  .use('/static', gzippo.staticGzip publicDir, maxAge: ONE_YEAR)
  # Gzip dynamically rendered content
  .use(express.compress())
  .use(app.scripts(store))

  # Add browserchannel client-side scripts to model bundles created by store,
  # and return middleware for responding to remote client messages
  .use(racerBrowserChannel store)
  # Adds req.getModel method
  .use(store.modelMiddleware())


  .use(ipMiddleware)

  # Creates an express middleware from the app's routes
  .use(app.router())
  .use(expressApp.router)
  .use(serverError())

expressApp.all '*', (req, res, next) ->
  next '404: ' + req.url
