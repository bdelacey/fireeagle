class FireEagle
  class Client
    attr_reader :access_token, :consumer, :format

    def initialize(options)
      options = {
        :debug  => false,
        :format => FireEagle::FORMAT_XML
      }.merge(options)
    
      # symbolize keys
      options.map do |k,v|
        options[k.to_sym] = v
      end
      raise FireEagle::ArgumentError, "OAuth Consumer Key and Secret required" if options[:consumer_key].nil? || options[:consumer_secret].nil?
      @consumer = OAuth::Consumer.new(options[:consumer_key], options[:consumer_secret])
      @debug = options[:debug]
      @format = options[:format]
      if options[:access_token] && options[:access_token_secret]
        @access_token = OAuth::Token.new(options[:access_token], options[:access_token_secret])
      else
        @access_token = nil
      end
    end
    
    def request_token_url
      response = get(FireEagle::REQUEST_TOKEN_PATH, :token => nil)
      @request_token = create_token(response)
      return "#{FireEagle::AUTHORIZATION_URL}?oauth_token=#{@request_token.token}"
    end
    
    def convert_to_access_token
      raise FireEagle::ArgumentError, "call #request_token_url and have user authorize the token first" if @request_token.nil?
      response = get(FireEagle::ACCESS_TOKEN_PATH, :token => @request_token)
      @access_token = create_token(response)
    end

    def get_access_token
      raise FireEagle::ArgumentError, "OAuth Access Token Required" unless debug?
      response = get(FireEagle::REQUEST_TOKEN_PATH, :token => nil)
      request_token = create_token(response)
    
      ## User interaction required
    
      puts "Authorize this: #{FireEagle::AUTHORIZATION_URL}?oauth_token=#{request_token.token}"
      print "<waiting>"
      $stdin.gets
    
      ## Back to our regularly scheduled access token retrieval
    
      response = get(FireEagle::ACCESS_TOKEN_PATH, :token => request_token)
      @access_token = create_token(response)
      puts "Access token: #{@access_token.inspect}"
    end

    def json?
      format == FireEagle::FORMAT_JSON
    end

    def lookup(params)
      get_access_token unless @access_token

      response = get(FireEagle::LOOKUP_API_PATH + ".#{format}", :params => params)
    
      puts response.body if debug?
    
      if json?
        JSON.parse(response.body)
      else
        response.body
      end
    end

    def update(params = {})
      get_access_token unless @access_token

      params.map do |k,v|
        params[k.to_sym] = v
      end

      params = params.reject { |key, value| !FireEagle::UPDATE_PARAMS.include?(key) }
      raise FireEagle::ArgumentError, "Requires all or none of :lat, :lon" unless params.has_all_or_none_keys?(:lat, :lon)
      raise FireEagle::ArgumentError, "Requires all or none of :mnc, :mcc, :lac, :cellid" unless params.has_all_or_none_keys?(:mnc, :mcc, :lac, :cid)
    
      response = post(FireEagle::UPDATE_API_PATH + ".#{format}", :params => params)
    
      puts response.body if debug?

      if json?
        JSON.parse(response.body)
      else
        response.body
      end
    end

    def user
      get_access_token unless @access_token

      response = get(FireEagle::USER_API_PATH + ".#{format}")

      puts response.body if debug?

      if json?
        JSON.parse(response.body)
      else
        response.body
      end
    end
    alias_method :location, :user

    def xml?
      format == FireEagle::FORMAT_XML
    end

  protected

    def parse_response(doc)
      doc = Hpricot(doc) unless doc.is_a?(Hpricot::Doc)
      raise FireEagle::FireEagleException, doc.at("/rsp/err").attributes["msg"] if doc.at("/rsp").attributes["stat"] == "fail"
      FireEagle::Location.new_from_xml(doc)
    end

    def create_token(response)
      token = Hash[*response.body.split("&").map { |x| x.split("=") }.flatten]
      OAuth::Token.new(token["oauth_token"], token["oauth_token_secret"])
    end

    def debug?
      @debug == true
    end

    def get(url, options = {})
      request(:get, url, options)
    end

    def post(url, options = {})
      request(:post, url, options)
    end

    def request(method, url, options)
      options = {
        :params => {},
        :token  => access_token
      }.merge(options)

      request_uri = URI.parse(FireEagle::SERVER + url)
      http = Net::HTTP.new(request_uri.host, request_uri.port)
      if FireEagle::SERVER =~ /https:/
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      request = nil
      if method == :post
        request = Net::HTTP::Post.new(request_uri.path)
        request.set_form_data(options[:params])
      elsif method == :get
        qs = options[:params].collect { |k,v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v.to_s)}" }.join("&")
        request = Net::HTTP::Get.new(request_uri.path + "?" + qs)
      end
      request.oauth!(http, consumer, options[:token])
      http.request(request)
    end

  end
end