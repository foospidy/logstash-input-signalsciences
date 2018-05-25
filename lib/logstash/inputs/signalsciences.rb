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
  config :from, :validate => :number, :default => 600
  # Debug for plugin development.
  config :debug, :validate => :boolean, :default => false

  # Set how frequently messages should be sent.
  #
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

    # check if from value is 5 minutes or less
    if @from <= 300
      @logger.warn("from value is 5 minutes or less, increasing from value to 10 minutes.")
      @from = 600
    end

    # check if from value is greater than 24 hours
    if @from > 86400
      @logger.warn("from value is greater than 24 hours, reducing from value to 24 hours.")
      @from = 86400
    end

    # set interval to value of from @from minus one minute
    interval = @from

    @logger.info("Fetching Signal Sciences request data every #{interval / 60} minutes.")
  end # def register

  def run(queue)
    # we can abort the loop if stop? becomes true
    while !stop?
      @login.body = URI.encode_www_form({"email" => @email, "password" => @password})

      if fetch(queue)
        @logger.info("Requests feed retreived successfully.")
      end

      # because the sleep interval can be big, when shutdown happens
      # we want to be able to abort the sleep
      # Stud.stoppable_sleep will frequently evaluate the given block
      # and abort the sleep(@interval) if the return value is true
      #Stud.stoppable_sleep(@interval) { stop? }
      Stud.stoppable_sleep(@interval) { stop? }
    end # loop
  end # def run

  def fetch(queue)
    begin
      response = @http.request(@login)
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
      t = Time.now.strftime("%Y-%m-%d %H:%M:0")
      dt = DateTime.parse(t)
      timestamp_until = dt.to_time.to_i - 300 # now - 5 minutes
      timestamp_from = (timestamp_until - @from) - 300 # @from - 5 minutes

      # Set up iniital get request and initial next_uri
      get = Net::HTTP::Get.new("/api/v0/corps/#{@corp}/sites/#{@site}/feed/requests?from=#{timestamp_from}&until=#{timestamp_until}")
      next_uri = "not empty on first pass"

      # Loop through results until next_uri is empty.
      while !next_uri.empty?
        get["Authorization"] = "Bearer #{token}"

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
          @logger.warn("get: #{json['message']} #{token}")
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
              @logger.info("payload['headersIn'] is empty for id #{payload['id']}, skipping append.")
            end

            # explode headersOut out to headerOut entries
            temp = {}
            begin
              payload['headersOut'].each { |k,v| temp[k] = v }
              payload["headerOut"] = temp
            rescue NoMethodError
              @logger.info("payload['headersOut'] is empty for id #{payload['id']}, skipping append.")
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
