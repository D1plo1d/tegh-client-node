// Coffeescript 1.0 and 2.0 respectively. Comment out the one you aren't using.
require('coffee-script/register');
// require('coffee-script-redux/register');

MDNS = require('./mdns');
Client = require('./client');
certs = require('./certs');

module.exports = {
  discovery: new MDNS(),
  Client: Client,
  addCert: certs.addCert
};