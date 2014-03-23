EventEmitter = require('events').EventEmitter
WebSocket = require('ws')
request = require 'request'
FormData = require 'form-data'
fs = require 'fs-extra'
flavoredPath = require ("flavored-path")
_ = require('lodash')
S = require('string')
certs = require('./certs')
SelfSignedHttpsAgent = require("./self_signed_https_agent")

module.exports = class Client extends EventEmitter
  blocking: false

  constructor: (@opts) ->
    defaultOpts =
      processEvent: undefined
      port: 2540
      address: null
      path: null
      user: null
      password: null
      addCert: false
    @opts = _.defaults @opts, defaultOpts
    @data = {}
    @_knownHosts = certs.knownHosts()
    @knownName = _.find(@_knownHosts, printer: @opts.name)?
    @host = @opts.address
    @host = "#{@opts.user}:#{@opts.password}@#{@host}" if @opts.user?
    url = "wss://#{@host}:#{@opts.port}#{@opts.path}socket"
    agent = new SelfSignedHttpsAgent()
    agent.once "cert", @_onCert
    @ws = new WebSocket url,
      webSocketVersion: 8
      # rejectUnauthorized: false
      agent: agent
    @ws
    .on('open', @_onOpen)
    .on('close', @_onClose)
    .on('message', @_onMessage)
    .on('error', @_onError)
    .on('timeout', -> @_onTimeout)

  send: (action, data) =>
    msg = action: action, data: data
    @blocking = true
    try
      @_attemptSend(msg)
    catch e
      @emit "error", {message: e}
      @_unblock()

  _attemptSend: (msg) =>
    return @_addJob(msg) if msg.action == "add_job"
    # console.log json
    @ws.send JSON.stringify msg

  # sends the add_job command as a http post multipart form request
  _addJob: (msg) =>
    filePath = msg.data

    if !filePath? or filePath.length == 0
      throw "add_job requires a file path (ex: add_job ~/myfile.gcode)"
    unless fs.existsSync filePath
      throw "No such file: #{filePath}"

    throw "#{filePath} is not a file" if fs.lstatSync(filePath).isDirectory()

    form = new FormData()

    form.append('file', fs.createReadStream(filePath))

    opts =
      protocol: "https:"
      host: @opts.address.split("@")[1] || @opts.address
      port: @opts.port
      path: "#{@opts.path}?session_uuid=#{@session_uuid}"
      auth: @opts.address.split("@")[0]
      rejectUnauthorized: false
    form.submit opts, (err, res) =>
      emitErr = (msg) => @emit "tegh_error", message: msg.toString()
      if err?
        emitErr err
      else if !(200 <= res.statusCode < 300 )
        res.once 'data', emitErr
      else
        @emit "ack", "Job added."
      @_unblock()

  _onCert: (@cert) =>
    @cert.printer = @opts.path.split("/")[2]
    @knownCert = _.find(@_knownHosts, @cert)?
    return if @knownCert
    if @opts.cert? and _.isEqual @opts.cert, @cert
      certs.addCert(@cert)
      @knownCert = true
      @opts.knownName = true
    else
      @emit "error", @opts.address, @cert
      @close()

  _onOpen: =>
      @emit "connect", @ws

  _onMessage: (m) =>
    messages = JSON.parse m
    (@opts.processEvent || @processEvent)?(event) for event in messages

  processEvent: (event) =>
    syncError = event.type == "error" and S(event.data.type).endsWith(".sync")
    @_unblock() if event.type == "ack" or syncError
    return if event.type == 'ack'
    target = event.target
    switch event.type
      when 'initialized'
        v.id = k for k, v of event.data
        _.merge @data, event.data
        @session_uuid = @data.session.uuid
      when 'change' then _.merge @data[target], event.data
      when 'rm' then delete @data[target]
      when 'add'
        event.data.id = target
        @data[target] = event.data
      when 'error'
        @emit "error", event.data.message
      else
        @emit "error", new Exception "unrecognized event: #{event}"
    @emit event.type, event.data

  _unblock: ->
    @blocking = false
    @emit "unblocked"

  close: =>
    try @ws.close()
    # Ignore errors after closing
    try
      @ws.removeAllListeners()
      @ws.on "error", ->
    @emit "close"
    @removeAllListeners()

  _onClose: =>
    @close()

  _onError: (e) =>
    @unauthorized = e.toString().indexOf("unexpected server response (401)") > -1
    @emit "error", e
    @close()

  _onTimeout: (e) =>
    @timedOut = true
    @emit "error", "connection timeout"
    @close()
