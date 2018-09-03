configure = (cfg) ->

  debug "Loading zones"

  zones = new Zones()

  # Enumerate the domains listed in the database with a "records" field.
  {rows} = await cfg.prov.query "#{couchapp.id}/domains", include_docs:true

  for rec in rows ? []
    do (rec) ->
      doc = rec.doc
      return if not doc?
      if doc.ENUM
        debug 'Ignoring ENUM document', doc
        return
      else
        zone = new Zone doc.domain, doc, cfg.serial
      zones.add_zone zone

  # Add any other records (hosts, ..)
  {rows} = await cfg.prov.query "#{couchapp.id}/names"

  for rec in rows ? []
    do (rec) ->
      domain = rec.key
      return unless domain?
      zone = zones.get_zone(domain) ? zones.add_zone new Zone domain, {}
      zone.add_record rec.value

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
  await update db, couchapp

get_serial = ->
  now = new Date()
  date = parseInt now.toJSON().replace(/[^\d]/g,'').slice(0,8)
  seq = Math.floor(100*(now.getHours()*60+now.getMinutes())/1440)
  date*100+seq

main = ->
  cfg = {}

  assert process.env.DNS_PREFIX_ADMIN?, 'Please provide DNS_PREFIX_ADMIN'
  cfg.prov = new PouchDB process.env.DNS_PREFIX_ADMIN
  cfg.serial = "#{get_serial()}"
  cfg.web_port = process.env.DNS_WEB_PORT

  install cfg.prov

  cfg.server = dns.createServer {}

  cfg.server.listen process.env.DNS_PORT ? 53

  monitor = ->
    changes = cfg.prov.changes
      live: true
      include_docs: true
      filter: "#{couchapp.id}/changes"
      since: 'now'

    changes.on 'change', ->
      configure cfg

    changes.on 'error', (err) ->
      debug "Changes error: #{err}"
      monitor()

  # Start monitoring changes
  monitor()

  # Initial configuration
  configure cfg
  return

dns = require "./src/dns"
Zone = dns.Zone
Zones = dns.Zones

pkg = require './package.json'
debug = (require 'debug') pkg.name
assert = require 'assert'
PouchDB = require 'ccnq4-pouchdb'
update = require 'nimble-direction/update'
Zappa = require 'zappajs'

module.exports = {configure,main,install,get_serial}
if require.main is module
  main()
