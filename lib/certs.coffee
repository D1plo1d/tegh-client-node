flavoredPath = require ("flavored-path")
fs = require 'fs-extra'

certFile = flavoredPath.resolve "~/.tegh/known_hosts.json"

module.exports =
  addCert: (cert) ->
    knownHosts = module.exports.knownHosts()
    knownHosts.push cert
    fs.writeFileSync certFile, JSON.stringify knownHosts

  knownHosts: ->
    try
      require certFile
    catch
      return []
