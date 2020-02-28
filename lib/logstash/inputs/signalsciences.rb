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
  config :password, :validate => :string, :default => ""
  # Signal Sciences API access token.
  config :token, :validate => :string, :default => ""
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
  # A hash of siteinfo endpoints in this format : "name" => "endpoint".
  # The name and the siteinfo will be passed in the outputed event
  # API to be used. The default is feed/requests to list the requests over a given period of time.  One could utilize "agents" to get the status of all your agents.
  config :endpoints, :validate => :hash, :default =>  {"feed_requests"=>{"endpoint"=>"feed/requests", "from_until"=>"true"}}

  # Define the target field for placing the received data. If this setting is omitted, the data will be stored at the root (top level) of the event.
  config :target, :validate => :string

  # get_endpoints
  config :get_endpoints, :validate => :array, :default => '@get_endpoints'

  public
  def register
    @host = Socket.gethostname.force_encoding(Encoding::UTF_8)
    
    @logger.info("Registering signalsciences Input", :password => @password, :email => @email, :corp => @corp, :site => @site, :from => @from, interval => @interval, endpoints => @endpoints )
    # check if from value is less than 1 min

    @http = Net::HTTP.new('dashboard.signalsciences.net', 443)
    @http.use_ssl = true
    @http.set_debug_output($stdout) if @debug
    #@apiendpoint = "/api/v0/corps/#{@corp}/sites/#{@site}/"
    # set version for UA string
    @version = "1.3.0"
    # set interval to value of from @from minus five minutes
    @interval = @from
    t = Time.now.utc.strftime("%Y-%m-%d %H:%M:0")
    dt = DateTime.parse(t)
    ts_until = dt.to_time.to_i - 300 # now - 5 minutes
    ts_from = (ts_until - @from) # @until - @from
    @timestamp_until = ts_until
    @timestamp_from = ts_from
  end

  public
  def run(queue)
    while !stop?
      if fetch(queue)
        @logger.debug("Signal Sciences requests feed retreived successfully.")
      else
        @logger.warn("Signal Sciences problem retreiving request!")
      end
      # because the sleep interval can be big, when shutdown happens
      # we want to be able to abort the sleep
      # Stud.stoppable_sleep will frequently evaluate the given block
      # and abort the sleep(@interval) if the return value is true
      #Stud.stoppable_sleep(@interval) { stop? }
      @logger.debug("Signal Sciences Sleep: #{@interval}")
      @timestamp_from = @timestamp_until
      Stud.stoppable_sleep(@interval) { stop? }
      t = Time.now.utc.strftime("%Y-%m-%d %H:%M:0")
      dt = DateTime.parse(t)
      @timestamp_until = dt.to_time.to_i - 300 # now - 5 minutes
    end #end loop
  end

  def fetch(queue)
    setup_endpoints!
    @get_endpoints.each do |name, api_endpoint|
      @logger.debug("Signal Scienses name: #{name}")
      @logger.debug("Signal Scienses endpoint: #{api_endpoint}")
      request = get_request(queue, api_endpoint, name)
      response = @http.request(request)
      if response.code != "200"
        return check_response_code!(response.code)
      else
        handle_success!(queue, name, response)
      end
    end
  end

  private
  def setup_endpoints!
    @logger.info("Registering signalsciences Input", interval => @interval, endpoints => @endpoints )
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
    @get_endpoints = Hash[@endpoints.map {|name, endpoint| [name, process_endpoint!(endpoint)] }]
  end

  private
  def process_endpoint!(endpoint_or_fu)
    site=nil
    if endpoint_or_fu.is_a?(String)
      raise LogStash::ConfigurationError, "Invalid endpoints spec: '#{endpoint_or_fu}', expected a Hash!"
    elsif endpoint_or_fu.is_a?(Hash)
      endpoint_spec = Hash[endpoint_or_fu.clone.map {|k,v| [k.to_sym, v] }]
      @logger.debug("Signal Sciences: endpoint_spec: #{endpoint_spec}")
      from_ut = endpoint_spec.delete(:from_until)
      @logger.debug("Signal Sciences: from_ut: #{from_ut}")
      site = endpoint_spec.delete(:site)
      @logger.debug("Signal Sciences: site: #{site}")
      endpoint = endpoint_spec.delete(:endpoint)
      @logger.debug("Signal Sciences: endpoint: #{endpoint}")
    else
      raise LogStash::ConfigurationError, "Invalid endpoints spec: '#{endpoint_or_fu}', expected a Hash!"
    end
   
    if from_ut == "true"
      if site.nil?
        api_endpoint = "/api/v0/corps/#{@corp}/sites/#{@site}/#{endpoint}?from=#{@timestamp_from}&until=#{@timestamp_until}"
      else
        api_endpoint = "/api/v0/corps/#{@corp}/sites/#{site}/#{endpoint}?from=#{@timestamp_from}&until=#{@timestamp_until}"
      end
    else
      if site.nil?
        api_endpoint = "/api/v0/corps/#{@corp}/sites/#{@site}/#{endpoint}"
      else
        api_endpoint = "/api/v0/corps/#{@corp}/sites/#{site}/#{endpoint}"
      end
    end
    @logger.debug("Signal Sciences: endpoint: #{api_endpoint}")
    return api_endpoint
  end

  private
  def get_request(queue, api_endpoint, name)
    if @token.to_s.empty?
      bearer_token = setup_auth_requests!
      get = Net::HTTP::Get.new("#{api_endpoint}")
      get["Authorization"] = "Bearer #{bearer_token}"
      get['User-Agent'] = "logstash-signalsciences/#{@version}"
      # Set up iniital get request and initial next_uri
      @logger.debug("Requesting data: #{api_endpoint}")
    else
      get = Net::HTTP::Get.new("#{api_endpoint}")
      get["x-api-user"] = @email
      get["x-api-token"] = @token
      get['User-Agent'] = "logstash-signalsciences/#{@version}"
      # Set up iniital get request and initial next_uri
      @logger.debug("Requesting x-api data: #{api_endpoint}")
    end
    return get
  end

  private
  def handle_success!(queue, name, response)
    body = response.body
    # If there is a usable response. HEAD requests are `nil` and empty get
    # responses come up as "" which will cause the codec to not yield anything
    if body && body.size > 0
      json = JSON.parse(body)
      if json.has_key? "message"
        # some error occured, report it.
        @logger.warn("Error accessing API status code: #{response.code} with message: #{json['message']}")
        return
      end  
      if json.has_key? "data"
        json['data'].each do |payload|
          process_payload!(payload, name, queue)
        end
      end
      if json.has_key? "next:uri"
        next_uri = json['next']['uri']
        @logger.debug("Additional processing of next:uri: #{next_uri}")
        while !next_uri.empty?
          if @debug
            logger.info("Next URI: #{next_uri}")
          end
          get_uri = Net::HTTP::Get.new("#{next_uri}")
          if @token.to_s.empty?
            #bearer_token = setup_auth_requests!
            get_uri["Authorization"] = "Bearer #{bearer_token}"
            get_uri['User-Agent'] = "logstash-signalsciences/#{@version}"
          else
            get_uri["x-api-user"] = @email
            get_uri["x-api-token"] = @token
            get_uri['User-Agent'] = "logstash-signalsciences/#{@version}"
          end
          begin
            response_uri = @http.request(get_uri)
          rescue
            @logger.warn("Could not reach API endpoint to retreive reqeusts feed!")
            return false
          end
          if response_uri.code != "200"
            return check_response_code!(response_uri.code)
          else
            json = JSON.parse(response_uri.body)
          end
          if json['data'].size > 0
            json['data'].each do |payload_uri|
              process_payload!(payload_uri, name, queue)
            end
          end
          next_uri = json['next']['uri']
        end
      end
    end
  end

  private
  def setup_auth_requests!
    login = Net::HTTP::Post.new("/api/v0/auth")
    login['User-Agent'] = "logstash-signalsciences/#{@version}"
    login.body = URI.encode_www_form({"email" => @email, "password" => @password})
    begin
      loginresponse = @http.request(login)
      @logger.debug("Signal Scienses login response: #{loginresponse.code}")
    rescue
      @logger.warn("Signal Scienses could not reach API endpoint to login!")
      return false
    end
    if loginresponse.code != "200"
      return check_response_code!(loginresponse.code)
    end
    json = JSON.parse(loginresponse.body)
    if json.has_key? "message"
      # failed to login
      @logger.warn("Signal Scienses login failed: #{json['message']}")
      return false
    end
    bearer_token = json['token']
    @logger.debug("Signal Scienses Bearer Token: #{bearer_token}")
    return bearer_token
  end

  private
  def check_response_code!(res_code)
    if res_code == "524"
      @logger.warn("524 - Origin Timeout!")
      @logger.info("Another attempt will be made later.")
      return false
    end
    if res_code == "429"
      @logger.warn("429 - Too Many Requests!")
      @logger.info("API request throttling as been triggered, another attempt will be made later. Contact support if this error continues.")
      return false
    end
    if res_code == "404"
      @logger.warn("404 - Not Found!")
      return false
    end
    if res_code == "401"
      @logger.warn("401 - Unauthorized!")
      return false
    end
    @logger.warn("Non-200 return enable debug to troubleshoot: #{res_code}")
    return false
  end

  private
  def process_payload!(payload, name, queue)
    # explode headersIn out to headerIn entries
    temp = {}
    if payload.has_key? "headersIn"
      begin
        payload['headersIn'].each { |k,v| temp[k] = v }
        payload["headerIn"] = temp
      rescue NoMethodError
        if @debug
          @logger.debug("payload['headersIn'] is empty for id #{payload['id']}, skipping append.")
        end
      end
    end
    # explode headersOut out to headerOut entries
    temp = {}
    if payload.has_key? "headersOut"
      begin
        payload['headersOut'].each { |k,v| temp[k] = v }
        payload["headerOut"] = temp
      rescue NoMethodError
        if @debug
          @logger.debug("payload['headersOut'] is empty for id #{payload['id']}, skipping append.")
        end
      end
    end
    # explode tags out to tag entries
    temp = {}
    if payload.has_key? "tags"
      payload['tags'].each do |x|
        temp[x['type']] = x
      end
      payload.delete('tags')
    end
    payload['tag'] = temp
    payload['logstash_host.name'] = @host

    event = LogStash::Event.new(payload)
    event.tag(name)
    decorate(event)
    queue << event
  end

  def stop
    # nothing to do in this case so it is not necessary to define stop
    # examples of common "stop" tasks:
    #  * close sockets (unblocking blocking reads/accepts)
    #  * cleanup temporary files
    #  * terminate spawned threads
  end
end # class LogStash::Inputs::Signalsciences
