module Jnctn

  module Xmpp

    JID = "testing"

    class AuthCommandServiceHelper

      def initialize(stream, jid, pass)
        @stream = stream
        @jid = jid
        @pass = pass
      end

      def authorize
        iq = build_auth_command_iq
        @stream.send_with_id(iq) { |reply|
          puts "found reply from authorization"
        }
      end

      private

      def validate_response

      end

      def build_auth_command_iq
        iq  = Jabber::Iq.new(:set, "commands.auth.xmpp.onsip.com")
        cmd  = Jabber::Command::IqCommand.new('authorize-plain')
        x_form = Jabber::Dataforms::XData.new(:submit)

        field = Jabber::Dataforms::XDataField.new('sip-address')
        field.value = @jid
        x_form.add(field)

        field = Jabber::Dataforms::XDataField.new('password')
        field.value = @pass
        x_form.add(field)

        field = Jabber::Dataforms::XDataField.new('auth-for-all')
        field.value = true;
        x_form.add(field)

        field = Jabber::Dataforms::XDataField.new('jid')
        field.value = "#{@jid}/#{JID}";
        x_form.add(field)

        cmd.add(x_form)
        iq.add(cmd)
        iq
      end

    end # AuthCommandServiceHelper

    class ActiveCallsPubSubServiceHelper

      def initialize(stream, jid)
        @stream = stream
        @jid = jid
      end

      ##
      # shows all subscriptions on the given node
      # return:: [Array] of [Jabber::Pubsub::Subscription]
      def get_subscriptions_from_node
        iq = basic_pubsub_active_calls_query(:get)

        entities = iq.pubsub.add(REXML::Element.new('subscriptions'))
        entities.attributes['node'] = "/me/#{@jid}"

        res = []
        @stream.send_with_id(iq) { |reply|
          if reply.pubsub.first_element('subscriptions')
            reply.pubsub.first_element('subscriptions').each_element('subscription') { |subscription|
              res << Jabber::PubSub::Subscription.import(subscription)
            }
          end
        }
        res
      end

      ##
      # subscribe to a node unless a subscription exists.
      # in which case configure node
      # return:: [Boolean] success or failure
      def subscribe_to_or_configure_node
        subscriptions = get_subscriptions_from_node

        res = nil

        subscriptions.map do |sub|
          if (sub.jid == "#{@jid}/#{JID}")
            res = configure_node sub.subid
            return
          end
        end

        res = subscribe_to_node
      end

      ##
      # subscribe to node
      def subscribe_to_node
        iq = basic_pubsub_active_calls_query(:set)

        subscribe = REXML::Element.new('subscribe')
        subscribe.attributes['node'] =  "/me/#{@jid}"
        subscribe.attributes['jid'] = "#{@jid}/#{JID}"

        iq.pubsub.add(subscribe)

        res = nil

        @stream.send_with_id(iq) do |reply|
          pubsubanswer = reply.pubsub
          if pubsubanswer.first_element('subscription')
            res = PubSub::Subscription.import(pubsubanswer.first_element('subscription'))
          end
        end

        res
      end

      ##
      # configure or refresh subscription
      def configure_node(subid)
        options = {}

        options["pubsub#subscription_type"] = "items"
        options["pubsub#subscription_depth"] = "all"
        options["pubsub#expires"] = Time.new

        iq = basic_pubsub_active_calls_query(:set)
        iq.pubsub.add(Jabber::PubSub::SubscriptionConfig.new("/me/#{@jid}", "#{@jid}/#{JID}", options, subid))

        @stream.send_with_id(iq) do |reply|
          pubsubanswer = reply.pubsub
        end
      end

      private

      ##
      # helper
      def basic_pubsub_active_calls_query(type)
        iq = Jabber::Iq.new(type, 'pubsub.active-calls.xmpp.onsip.com')
        iq.add(Jabber::PubSub::IqPubSub.new)
        iq.from = @jid #.strip
        iq
      end

    end # ActiveCallsPubSubServiceHelper

    class ActiveCallItem

      attr_accessor :publish_time, :call_id, :from_uri, :to_uri,
        :to_aor, :call_setup_id, :from_display, :to_display, :length,
        :time_from_ringer, :time_from_answered, :time_hung_up,
        :dialog_state, :item_id, :flag_call_setup, :item_ended

      def initialize
        @time_from_answered = ""
        @time_from_ringer = ""
        @time_hung_up = ""
        @call_id = ""
        @from_uri = ""
      end

    end #ActiveCallItem

    class ActiveCallItems

      def initialize
        @calls = Hash.new(nil)
        @writers = Array.new
      end

      def register_writer(writer)
        @writers << writer
      end

      def add(item)
        if valid_id?(item)

          # we don't care to save music on hold
          return if moh?(item)

          # if making a call to yourself
          return if !item.from_uri.to_s.empty? && item.from_uri == item.to_uri

          if (item.dialog_state == 'created' ||
              item.dialog_state == 'requested')

            item.time_from_ringer = Time.now.utc

            # incoming call is setup
            item.flag_call_setup = true if call_setup?(item)

            hk = gen_key(item)
            @calls[hk] = Array.new if @calls[hk].nil?
            @calls[hk] << item

          elsif (item.dialog_state == 'confirmed')
            hk = gen_key(item)
            call_items = @calls[hk]

            # item should not be nil
            unless call_items.nil?
              # update answered timestamp
              call_items.each { |ci|
                if ci.item_id == item.item_id
                  ci.to_aor = item.to_aor
                  ci.time_from_answered = Time.now.utc
                  ci.dialog_state = 'confirmed'
                end
              }
            end

          elsif (item.dialog_state == 'retracted')
            # else throw an error
            return if item.nil?

            k = find_call_from_item_id(item.item_id)
            return if k.nil?

            if @calls[k].length > 1
              return @calls[k].reject! { |x| x.item_id == item.item_id }
            end

            call = @calls[k]

            if call.is_a?(Array) && call.length == 1
              c = call[0].clone
              c.time_hung_up = Time.now.utc
              c.length = 0
              if c.time_from_answered.is_a?(Time)
                c.length = (c.time_hung_up - c.time_from_answered).round
              end
              if c.dialog_state == 'confirmed'
                c.dialog_state = 'A'
              else
                c.dialog_state = 'U'
              end

              Thread.abort_on_exception = true
              @writers.each { |w|
                Thread.start(c) do |c|
                  w.write(c)
                end
              }
            end

            @calls.delete(k)

          end
        end
      end

      private

      def gen_key(call)
        hk = Digest::MD5.new << "#{call.call_id.to_s}#{call.from_uri.to_s}"
        hk.to_s
      end

      def moh?(call)
        call.to_uri.to_s.match('moh@')
      end

      def call_setup?(call)
        call.call_setup_id.to_s.length > 0 && call.dialog_state == 'requested'
      end

      def valid_id?(call)
        call.item_id.to_s.length > 0
      end

      def find_call_from_item_id(id)
        for k,v in @calls do
          for i in v
            return k if i.item_id == id
          end
        end
        nil
      end

    end # ActiveCallItems

    ##
    # Writers
    # output call records
    class ActiveCallWriter

      def write(c)
        str =  "#{c.call_id.to_s}, "
        str << "#{c.from_uri.to_s}, "
        str << "#{c.to_uri.to_s}, "
        str << "#{c.to_aor.to_s}, "
        str << "#{mysql_formatted_time(c.time_from_ringer)}, "
        str << "#{mysql_formatted_time(c.time_from_answered)}, "
        str << "#{mysql_formatted_time(c.time_hung_up)}, "
        str << "#{c.from_display.to_s}, "
        str << "#{c.to_display.to_s}, "
        str << "#{c.dialog_state.to_s} "
        str << "\n"
        puts str
      end

      def mysql_formatted_time(t)
        begin
          ft = t.strftime('%Y-%m-%d %H:%M:%S')
        rescue
          ft = ""
        end
        ft
      end

    end # ActiveCallWriter

    class ActiveCallWriter2Mysql < ActiveCallWriter

      def initialize(host, user, pass, db)
        begin
          @con = Mysql.new host, user, pass, db

          sql_create = \
            ("CREATE TABLE IF NOT EXISTS \
              calls (id INT PRIMARY KEY AUTO_INCREMENT, \
              call_id VARCHAR(100), \
              from_uri VARCHAR(50), \
              from_display_name VARCHAR(50), \
              to_uri VARCHAR(50), \
              to_display_name VARCHAR(50), \
              to_aor VARCHAR(50), \
              time_ringer_start DATETIME, \
              time_answered DATETIME, \
              time_hung_up DATETIME, \
              length INT, \
              state VARCHAR(50))")

          @con.query(sql_create)

        rescue Mysql::Error => e
          puts e.errno
          puts e.error
        end
      end

      def write(c)
        begin
          sql_insert = "INSERT INTO calls ("
          sql_insert << "call_id, "
          sql_insert << "from_uri, "
          sql_insert << "from_display_name, "
          sql_insert << "to_uri, "
          sql_insert << "to_display_name, "
          sql_insert << "to_aor, "
          sql_insert << "time_ringer_start, "
          sql_insert << "time_answered, "
          sql_insert << "time_hung_up, "
          sql_insert << "length, state) "
          sql_insert << "VALUES ("
          sql_insert << "'#{c.call_id.to_s}', "
          sql_insert << "'#{c.from_uri.to_s}', "
          sql_insert << "'#{c.from_display.to_s}', "
          sql_insert << "'#{c.to_uri.to_s}', "
          sql_insert << "'#{c.to_display.to_s}', "
          sql_insert << "'#{c.to_aor.to_s}', "
          sql_insert << "'#{mysql_formatted_time(c.time_from_ringer)}', "
          sql_insert << "'#{mysql_formatted_time(c.time_from_answered)}', "
          sql_insert << "'#{mysql_formatted_time(c.time_hung_up)}', "
          sql_insert << "'#{c.length.to_s}', '#{c.dialog_state.to_s}')"

          @con.query(sql_insert)
        rescue Mysql::Error => e
          puts e.errno
          puts e.error
        end
      end

    end # ActiveCallWriter2Mysql

    class ActiveCallWriter2Csv < ActiveCallWriter

      def initialze(file)
        @file = file if File.exists?(file)
      end

      def write(c)
        File.open(@file, "a+") do |f|
          str =  "#{c.call_id.to_s}, "
          str << "#{c.from_uri.to_s}, "
          str << "#{c.to_uri.to_s}, "
          str << "#{c.to_aor.to_s}, "
          str << "#{mysql_formatted_time(c.time_from_ringer)}, "
          str << "#{mysql_formatted_time(c.time_from_answered)}, "
          str << "#{mysql_formatted_time(c.time_hung_up)}, "
          str << "#{c.from_display.to_s}, "
          str << "#{c.to_display.to_s}, "
          str << "#{c.dialog_state.to_s} "
          str << "\n"
          f.write str
        end
      end

    end # ActiveCallWriter2Csv

    ##
    # Configuration
    class ClientConfig
      DEFAULT_CONFIG_FILE = "xmpp_client.yaml"

      attr_accessor :file

      def initialize
        @file = "#{File.expand_path File.dirname(__FILE__)}/#{DEFAULT_CONFIG_FILE}"
        unless File.exist?(@file)
          File.open(@file, "w") do |f|
            init_config_hash
            f.write(@config.to_yaml)
          end
        else
          File.open(@file) { |f| @config = YAML::load(f) }
        end
      end

      def aors(id)
        @config[id][:aors]
      end

      def adapters(id)
        @config[id][:adapters]
      end

      def add_aor(id, aor = nil, password = nil)
        @config[id][:aors] << { :aor => aor, :password => password }
      end

      def add_adapter(id, adapter)
        @config[id][:adapters] << adapter
      end

      private

      def init_config_hash
        @config = Hash.new(nil)
        @config[1] = { :aors => [{ :aor => "", :password => "" }] }
        @config[1][:adapters] = [{ :mysql => {:db_user => "", :db_password => "", :host => "", :db => "" } }]
        @config
      end

    end # ClientConfig

    class ActiveCallsFacade

      DEFAULT_CONFIG_ID = 1

      def initialize
        @accounts = Array.new
        @connections = Hash.new(nil)
        @config = Jnctn::Xmpp::ClientConfig.new
        @calls = Jnctn::Xmpp::ActiveCallItems.new

        @config.adapters(DEFAULT_CONFIG_ID).each do |adapter|
          adapter.each do |k,v|

            case k
            when :mysql
              @calls.register_writer(Jnctn::Xmpp::ActiveCallWriter2Mysql.new(v[:host], v[:db_user], v[:db_password], v[:db]))
            when "csv"
              @calls.register_writer(Jnctn::Xmpp::ActiveCallWriter2Csv.new(v[:file]))
            else
              @calls.register_writer(Jnctn::Xmpp::ActiveCallWriter.new)
            end
          end
        end
      end

      def init
        aors = @config.aors(DEFAULT_CONFIG_ID)
        aors.each do |aor|
          @accounts << {:jid => aor[:aor], :pass => aor[:password] }
        end

        @accounts.map do |account|
          authorize(account)
        end

        # re-authorize
        Thread.start do
          sleep(45 * 60)
          init()
        end
      end

      def handle_iq(iq)
        puts "logging iq ..."
      end

      def handle_message(message)
        event =  message.first_element('event')
        if event
          items = event.first_element('items')
          if items
            items.each_element('item') { |item|
              call_item = Jnctn::Xmpp::ActiveCallItem.new
              call_item.item_id = item.attributes['id']
              active_call = item.first_element('active-call')
              if active_call
                call_item.to_uri = active_call.first_element_text('to-uri')
                call_item.to_aor = active_call.first_element_text('to-aor')
                call_item.call_id = active_call.first_element_text('call-id')
                call_item.from_uri = active_call.first_element_text('from-uri')
                call_item.to_display = active_call.first_element_text('to-display')
                call_item.to_display.to_s.gsub! /"/, ''
                call_item.from_display = active_call.first_element_text('from-display')
                call_item.from_display.to_s.gsub! /"/, ''
                call_item.dialog_state = active_call.first_element_text('dialog-state')
                call_item.call_setup_id = active_call.first_element_text('call-setup-id')
                @calls.add call_item
              end
            }
            retract = items.first_element('retract')
            if retract
              call_item = Jnctn::Xmpp::ActiveCallItem.new
              call_item.item_id = retract.attributes['id']
              call_item.dialog_state = 'retracted'
              @calls.add call_item
            end
          end
        end
      end

      def authorize(account)
        jid = account[:jid]
        pass = account[:pass]

        client = nil

        if !@connections[jid].nil?
          client = @connections[jid]
          if client.is_connected?
            puts "client #{jid} is connected"
          end
        else
          # Building up the connection
          client = Jabber::Client.new("#{jid}/#{JID}")
          client.connect

          client.auth(pass)

          client.add_iq_callback(200, self) { |iq|
            handle_iq(iq)
          }

          client.add_message_callback(200, self) { |message|
            handle_message(message)
          }

          @connections[jid] = client
        end

        puts ""
        puts "authorize"
        puts ""
        auth = Jnctn::Xmpp::AuthCommandServiceHelper.new(client, jid, pass)
        auth.authorize

        puts ""
        puts "subscribe"
        puts ""
        pubsub = Jnctn::Xmpp::ActiveCallsPubSubServiceHelper.new(client, jid)
        pubsub.subscribe_to_or_configure_node

      end

    end # ActiveCallsFacade

    def init
      ActiveCallsFacade.new.init
      while true do

      end
    end

  end
end
