#!/usr/bin/ruby -rubygems

require "xmpp_client_analytics/version"
require "xmpp_client_analytics/active_calls/active_calls"

require 'xmpp4r/iq'
require 'xmpp4r/command/iq/command'
require 'xmpp4r/dataforms'

require 'xmpp4r/pubsub/helper/nodehelper'
require 'xmpp4r/pubsub/helper/servicehelper'

require 'xmpp4r/rexmladdons'

require 'digest/md5'

require 'yaml'
require 'mysql'
require 'date'


Jabber::debug = true

include Jnctn::Xmpp

Jnctn::Xmpp.init()
