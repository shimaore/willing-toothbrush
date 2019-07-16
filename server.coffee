configure = (cfg) ->

  debug "Loading zones"

  zones = new Zones()

  debug 'Enumerate the domains listed in the database with a "records" field.'
  await cfg.prov
    .query couchapp.id, 'domains', include_docs:true
    .observe (rec) ->
      doc = rec.doc
      return if not doc?
      if doc.ENUM
        debug 'Ignoring ENUM document', doc
        return
      else
        debug 'new Zone', doc, cfg.serial
        zone = new Zone doc.domain, doc, cfg.serial
      zones.add_zone zone
      return

  debug 'Add any other records (hosts, ..)'
  await cfg.prov
    .query couchapp.id, 'names'
    .observe (rec) ->
      domain = rec.key
      return unless domain?
      debug 'add record', rec.value
      zone = zones.get_zone(domain) ? zones.add_zone new Zone domain, {}
      zone.add_record rec.value
      return

  new_serial = get_serial()
  if new_serial > cfg.serial
    cfg.serial = new_serial
  else
    cfg.serial++

  debug 'Reload zones', serial: cfg.serial
  cfg.server.reload zones

  return

couchapp = require './couchapp'

install = (db) ->
  debug 'Installing application in database'
  try await db.update couchapp

get_serial = ->
  now = new Date()
  date = parseInt now.toJSON().replace(/[^\d]/g,'').slice(0,8)
  seq = Math.floor(100*(now.getHours()*60+now.getMinutes())/1440)
  date*100+seq

main = ->
  debug 'Main'
  cfg = {}

  assert process.env.DNS_PREFIX_ADMIN?, 'Please provide DNS_PREFIX_ADMIN'
  cfg.prov = new CouchDB process.env.DNS_PREFIX_ADMIN
  cfg.serial = "#{get_serial()}"
  cfg.web_port = process.env.DNS_WEB_PORT

  await install cfg.prov

  debug 'Create server'
  cfg.server = dns.createServer {}

  cfg.server.listen process.env.DNS_PORT ? 53

  debug 'Start monitoring changes'
  cfg.prov.changes
    live: true
    include_docs: true
    # selector: $or: [ {type:'domain'}, {type:'host'} ] # only on CouchDB2?
    since: 'now'
  .filter ({type}) ->
    type is 'domain' or type is 'host'
  .observe ({_id}) ->
    debug "Reconfiguring due to #{_id}"
    do ->
      try
        await configure cfg
      catch error
        console.error "Reconfigure failed, will retry", error
        try
          await configure cfg
        catch error
          console.error "Configure failed (ignored)", error
      return
    return
  .catch (error) ->
    console.error 'Monitoring changes:', error
    process.exit 1

  debug 'Initial configuration'
  await configure cfg
  return cfg.server.statistics

dns = require "./src/dns"
Zone = dns.Zone
Zones = dns.Zones

pkg = require './package.json'
debug = (require 'debug') pkg.name
assert = require 'assert'
CouchDB = require 'most-couchdb/with-update'

module.exports = {configure,main,install,get_serial}
if require.main is module
  debug 'Starting'
  main()
  .then (statistics) ->
    debug 'Started'
    setInterval ->
      debug 'Requests', statistics.requests.toString(10)
    , 30*1000
  .catch (error) ->
    console.error 'Main failed', error
    process.exit 1
