EventEmitter = require('events').EventEmitter
WebSocket = require('ws')
request = require 'request'
FormData = require 'form-data'
fs = require 'fs-extra'
flavoredPath = require ("flavored-path")
_ = require('lodash')
S = require('string')
certs = require('./certs')

module.exports = class Client extends EventEmitter
  blocking: false

  constructor: (@opts) ->
    defaultOpts =
      processEvent: @processEvent
      port: 2540
      address: null
      path: null
      user: null
      password: null
      addCert: false
    @opts = _.defaults @opts, defaultOpts
    @data = {}
    @_knownHosts = certs.knownHosts()
    @host = @opts.address
    @host = "#{@opts.user}:#{@opts.password}@#{@host}" if @opts.user?
    url = "wss://#{@host}:#{@opts.port}#{@opts.path}socket"
    @.on "initialized", @_onInitialized
    @ws = new WebSocket url,
      webSocketVersion: 8
      rejectUnauthorized: false
    @ws
    .on('open', @_onOpen)
    .on('close', @_onClose)
    .on('message', @_onMessage)
    .on('error', @_onError)

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

  _onOpen: =>
    @cert = @ws._sender._socket.getPeerCertificate()
    @cert.printer = @opts.path.split("/")[2]
    @isKnownHost = _.find(@_knownHosts, @cert)?
    if !@isKnownHost and @opts.addCert
      certs.addCert(@cert)
    if @isKnownHost or @opts.addCert
      @emit "connect", @ws
    else
      @emit "error", @opts.address, @cert
      @removeAllListeners()
      @ws.close()

  _onInitialized: (data) =>
    @session_uuid = data.session.uuid

  _onMessage: (m) =>
    messages = JSON.parse m
    @opts.processEvent?(event) for event in messages

  processEvent: (event) =>
    syncError = event.type == "error" and S(event.data.type).endsWith(".sync")
    @_unblock() if event.type == "ack" or syncError
    return if event.type == 'ack'
    target = event.target
    switch event.type
      when 'initialized' then _.merge @data, event.data
      when 'change' then _.merge @data[target], event.data
      when 'rm' then delete @data[target]
      when 'add' then @data[target] = event.data
      when 'error'
        @emit "error", event.data.message
      else
        @emit "error", new Exception "unrecognized event: #{event}"
    @emit event.type, event.data

  _unblock: ->
    @blocking = false
    @emit "unblocked"

  _onClose: =>
    @emit "close"

  _onError: (e) =>
    @unauthorized = e.toString().indexOf("unexpected server response (401)") > -1
    @emit "error", e
    @removeAllListeners()


