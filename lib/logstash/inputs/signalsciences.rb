# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "stud/interval"
require "socket" # for Socket.gethostname
require "json"
require "date"

# Fetch Signal Sciences request data.
#

class LogStash::Inputs::Signalsciences < LogStash::Inputs::Base
  config_name "signalsciences"

  # If undefined, Logstash will complain, even if codec is unused.
  default :codec, "json"

  # Configurable variables
  # Signal Sciences API account username.
  config :email, :validate => :string, :default => "nobody@signalsciences.com"
  # Signal Sciences API password.
  config :password, :validate => :string, :default => "nobody"
  # Corp and site to pull data from.
  config :corp, :validate => :string, :default => "not_provided"
  config :site, :validate => :string, :default => "not_provided"
  # Number of seconds in the past to filter data on
  # This value will also be used to set the interval at which the API is polled.
  config :from, :validate => :number, :default => 300
  # Debug for plugin development.
  config :debug, :validate => :boolean, :default => false
  # The default, `600`, means fetch data every 10 minutes.
  config :interval, :validate => :number, :default => 600

  public
  def register
    @host = Socket.gethostname
    @http = Net::HTTP.new('dashboard.signalsciences.net', 443)
    @http.set_debug_output($stdout) if @debug
    @login = Net::HTTP::Post.new("/api/v0/auth")
    @get = Net::HTTP::Get.new("/api/v0/corps/#{@corp}/sites/#{@site}/feed/requests")
    @http.use_ssl = true

    # check if from value is less than 1 min
    if @from < 60
      @logger.warn("from value is less than 1 min, increasing from value to 1 minute.")
      @from = 60
    end

    # check if from value is greater than 24 hours
    if @from > 86400
      @logger.warn("from value is greater than 24 hours, reducing from value to 24 hours.")
      @from = 86400
    end

    # set interval to value of from @from minus five minutes
    @interval = @from

    # set version for UA string
    @version = "0.3.1"

    @logger.info("Fetching Signal Sciences request data every #{@interval / 60} minutes.")
  end # def register

  def run(queue)
    # we can abort the loop if stop? becomes true
    while !stop?
      @login['User-Agent'] = "logstash-signalsciences/#{@version}"
      @login.body = URI.encode_www_form({"email" => @email, "password" => @password})

      if fetch(queue)
        @logger.info("Requests feed retreived successfully.")
      else
        @logger.warn("Problem retreiving request!")
      end

      # because the sleep interval can be big, when shutdown happens
      # we want to be able to abort the sleep
      # Stud.stoppable_sleep will frequently evaluate the given block
      # and abort the sleep(@interval) if the return value is true
      #Stud.stoppable_sleep(@interval) { stop? }
      @logger.info("Sleep #{@interval}")
      Stud.stoppable_sleep(@interval) { stop? }
    end # loop
  end # def run

  def fetch(queue)
    begin
      response = @http.request(@login)
      @logger.warn("login response: #{response.code}")
    rescue
      @logger.warn("Could not reach API endpoint to login!")
      return false
    end

    json = JSON.parse(response.body)

    if json.has_key? "message"
      # failed to login
      @logger.warn("login: #{json['message']}")
      return false

    else
      token = json['token']
      # Both the from and until parameters must fall on full minute boundaries,
      # see https://docs.signalsciences.net/faq/extract-your-data/.
      t = Time.now.utc.strftime("%Y-%m-%d %H:%M:0")
      dt = DateTime.parse(t)
      timestamp_until = dt.to_time.to_i - 300 # now - 5 minutes
      timestamp_from = (timestamp_until - @from) # @until - @from

      if @debug
        hfrom = Time.at(timestamp_from).to_datetime
        huntil = Time.at(timestamp_until).to_datetime
        @logger.info("From #{hfrom} Until #{huntil}")
      end

      # Set up iniital get request and initial next_uri
      @logger.info("Requesting data: /api/v0/corps/#{@corp}/sites/#{@site}/feed/requests?from=#{timestamp_from}&until=#{timestamp_until}")
      get = Net::HTTP::Get.new("/api/v0/corps/#{@corp}/sites/#{@site}/feed/requests?from=#{timestamp_from}&until=#{timestamp_until}")
      next_uri = "not empty on first pass"

      # Loop through results until next_uri is empty.
      while !next_uri.empty?
        get["Authorization"] = "Bearer #{token}"
        get['User-Agent'] = "logstash-signalsciences/#{@version}"

        begin
          response = @http.request(get)
        rescue
          @logger.warn("Could not reach API endpoint to retreive reqeusts feed!")
          return false
        end
        json = JSON.parse(response.body)

        #check for message, error, e.g. missing query string parameter
        if json.has_key? "message"
          # some error occured, report it.
          @logger.warn("Error accessing API (#{token}), status code: #{response.code} with message: #{json['message']}")
          return false

        else
          # log json payloads
          json['data'].each do |payload|

            # explode headersIn out to headerIn entries
            temp = {}
            begin
              payload['headersIn'].each { |k,v| temp[k] = v }
              payload["headerIn"] = temp
            rescue NoMethodError
              if @debug
                @logger.debug("payload['headersIn'] is empty for id #{payload['id']}, skipping append.")
              end
            end

            # explode headersOut out to headerOut entries
            temp = {}
            begin
              payload['headersOut'].each { |k,v| temp[k] = v }
              payload["headerOut"] = temp
            rescue NoMethodError
              if @debug
                @logger.info("payload['headersOut'] is empty for id #{payload['id']}, skipping append.")
              end
            end

            # explode tags out to tag entries
            temp = {}
            payload['tags'].each do |x|
              temp[x['type']] = x
            end
            payload['tag'] = temp

            # add the event
            
            event = LogStash::Event.new("message" => payload, "host" => @host)

            decorate(event)
            queue << event
          end

          # get the next uri value
          next_uri = json['next']['uri']
          if @debug
            logger.info("Next URI: #{next_uri}")
          end

          # continue retreiving next_uri if it exists
          if !next_uri.empty?
            get = Net::HTTP::Get.new(next_uri)
          end
        end
      end
    end

    return true
  end

  def stop
    # nothing to do in this case so it is not necessary to define stop
    # examples of common "stop" tasks:
    #  * close sockets (unblocking blocking reads/accepts)
    #  * cleanup temporary files
    #  * terminate spawned threads
  end
end # class LogStash::Inputs::Signalsciences
