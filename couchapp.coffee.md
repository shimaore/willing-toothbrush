    pkg = require './package.json'
    id = "#{pkg.name}-#{pkg.version}-dns"

    ddoc =
      _id: "_design/#{id}"
      id: id
      package: pkg.name
      version: pkg.version
      language: 'javascript'
      views: {}
      filters: {}

    module.exports = ddoc

    {p_fun} = require 'coffeescript-helpers'

`changes` filter
----------------

Remember to update this filter if new doc.type's are handled by the views.

    ddoc.filters.changes = p_fun (doc,req) ->
        return doc.type? and (doc.type is 'domain' or doc.type is 'host')

`domains` view
--------------

    ddoc.views.domains =
      map: p_fun (doc) ->

        name_key = (name) ->
          name.split('').reverse().join('')+'~'

Only return documents that will end up as domains that can be served

        if doc.type? and doc.type is 'domain' and doc.records?

Sort the documents so that the sub-domains are listed first.

          emit name_key(doc.domain), null

`names` view
------------

The following view output the domain's name as key and a DNS record as content.

    ddoc.views.names =
      map: p_fun (doc) ->
        return unless doc.type? and doc.type

        is_true = (b) -> if b then true else false

        v4_loopback = (ip) ->
          is_true ip.match /^127\./

RFC 1918

        rfc_1918 = (ip) ->
          is_true ip.match /^10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168\./

RFC 3927

        rfc_3927 = (ip) ->
          is_true ip.match /^169\.254\.1\./

        v4_is_private = (ip) ->
          rfc_1918(ip) or rfc_3927(ip)

RFC 4291 (link-local)

        v6_linklocal = (ip) ->
          is_true ip.match /^fe[89ab]:/i

RFC 4193

        rfc_4193 = (ip) ->
          is_true ip.match /^f[cd]/i

RFC 4291 (multicast)

        v6_multicast = (ip) ->
          is_true ip.match /^ff/i

        v6_is_private = (ip) ->
          v6_linklocal(ip) or rfc_4193(ip) or v6_multicast(ip)

        ip_to_name = {}

        switch doc.type

          when 'host'

            host = doc.host

### Host-level records

            if doc.interfaces?

              # FIXME IPv6 addresses should be canonalized

              primary_v4 = null
              private_v4 = null
              primary_v6 = null
              for name, _ of doc.interfaces
                do (name,_) ->
                  fqdn = name+'.'+doc.host
                  if _.ipv4
                    ip_to_name[_.ipv4] = fqdn
                    if name is 'primary'
                      primary_v4 = _.ipv4
                    else
                      if not v4_is_private _.ipv4
                        primary_v4 ?= _.ipv4
                      else
                        private_v4 ?= _.ipv4
                    emit host,
                      prefix:name
                      class:'A',
                      value:_.ipv4
                  if _.ipv6
                    ip_to_name[_.ipv6] = fqdn
                    if name is 'primary'
                      primary_v6 = _.ipv6
                    else
                      if not v6_is_private _.ipv6
                        primary_v6 ?= _.ipv6
                    emit host,
                      prefix:name
                      class:'AAAA'
                      value:_.ipv6

If no public IPv4 is present, use a private IPv4 for the primary interface.

              primary_v4 ?= private_v4

              if primary_v4?
                ip_to_name[primary_v4] = doc.host
                emit host,
                  class:'A'
                  value:primary_v4

              if primary_v6?
                ip_to_name[primary_v6] = doc.host
                emit host,
                  class:'AAAA'
                  value:primary_v6


### SIP records

            domain = doc.sip_domain_name

            if domain?
              if doc.sip_profiles?

                for name, _ of doc.sip_profiles
                  do (name,_) ->
                    if _.ingress_sip_ip?

                      fqdn = name+'.'+domain

Different profiles with the same name in the same domain are reputed to be the same (i.e. equivalent routes in a cluster).
Note: SRV records must use names. So if `ip_to_name` does not have a mapping we use the host name and assume the best.
(Also, `ingress_sip_ip` and `egress_sip_ip` are supposed to be local addresses, so if the "interfaces" field is populated properly this shouldn't be an issue.)

                      _sip_udp = '_sip._udp.'

                      emit domain,
                        prefix:_sip_udp+'ingress-'+name
                        class:'SRV'
                        value:[
                          10
                          10
                          _.ingress_sip_port
                          ip_to_name[_.ingress_sip_ip] ? doc.host
                        ]

UDP NAPTR

                      emit domain,
                        prefix: 'ingress-'+name
                        class:'NAPTR'
                        value: [
                          10
                          10
                          's' # output is domain-name with SRV records (see rfc3404)
                          'SIP+D2U' # SIP over UDP (rfc3263)
                          ''
                          _sip_udp+'ingress-'+fqdn
                        ]

                      emit domain,
                        prefix:_sip_udp+'egress-'+name
                        class:'SRV'
                        value:[
                          10
                          10
                          _.egress_sip_port ? _.ingress_sip_port+10000
                          ip_to_name[_.egress_sip_ip ? _.ingress_sip_ip ] ? doc.host
                        ]
                      emit domain,
                        prefix: 'egress-'+name
                        class:'NAPTR'
                        value: [
                          10
                          10
                          's' # output is domain-name with SRV records (see rfc3404)
                          'SIP+D2U' # SIP over UDP (rfc3263)
                          ''
                          _sip_udp+'egress-'+fqdn
                        ]

              if doc.opensips?
                # FIXME detect whether proxy_ip is v4 or v6
                # and use A or AAAA accordingly

Note: if proxy_ip is not specified, opensips will be available on all interfaces. Pick the primary one for the public A record, in that case.

                if doc.opensips.proxy_ip? or primary_v4?
                  emit domain,
                    class:'A'
                    value: doc.opensips.proxy_ip ? primary_v4
                emit domain,
                  prefix:'_sip._udp'
                  class:'SRV'
                  value:[
                    10
                    10
                    doc.opensips.proxy_port ? 5060
                    ip_to_name[doc.opensips.proxy_ip] ? doc.host
                  ]
