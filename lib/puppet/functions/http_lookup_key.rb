# frozen_string_literal: true

require 'json'
require 'yaml'
require 'uri'
require 'net/http'
require '/etc/puppetlabs/puppet/env'

# TODO
class LookupKey
  def initialize(options, context)
    @context = context
    @options = options
    @type = @options.fetch(:type, 'yaml')
    @log = File.open('/var/log/lookup_key.log', 'a')

    @data = raw_data
  end

  def load_data_hash
    return {} unless @data.is_a?(Net::HTTPSuccess)

    case @type
    when 'json'
      JSON.parse @data.body
    when 'yaml'
      Puppet::Util::Yaml.safe_load @data.body
    end
  rescue Puppet::Util::Yaml::YamlLoadError => e
    raise Puppet::DataBinding::LookupError, _('Unable to parse %<message>s').format(message: e.message)
  end

  private

  def raw_data
    uri = URI.parse(@options['uri'])
    host = uri.host
    port = uri.port
    path = @context.interpolate(uri.request_uri)
    @http = Net::HTTP.new(host, port)
    @http.set_debug_output(@log)
    @http.use_ssl = true
    req = Net::HTTP::Get.new(path)
    req.basic_auth ENV['BASIC_USER'], ENV['BASIC_PASSWORD']
    @http.request req
  end
end

Puppet::Functions.create_function(:http_lookup_key) do
  # https://github.com/puppetlabs/puppet/blob/main/lib/puppet/functions/eyaml_lookup_key.rb
  dispatch :http_lookup_key do
    param 'String[1]', :key
    param 'Hash[String[1],Any]', :options
    param 'Puppet::LookupContext', :context
  end

  def http_lookup_key(key, options, context)
    return context.cached_value(key) if context.cache_has_key(key)

    data = context.cached_value(nil)
    if data.nil?
      data = LookupKey.new(options, context).load_data_hash
      context.cache(nil, data)
      # context.cache_all(data) if data.is_a? Hash
    end
    context.not_found unless data.include?(key)
    context.cache(key, data[key])
  end
end
