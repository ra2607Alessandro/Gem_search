require 'net/http'

class HttpClient
    def self.get(uri, request_id: Current.request_id, headers: {})
    u = URI(uri)
    req = Net::HTTP::Get.new(u)
    req['X-Request-ID'] = request_id if request_id
    headers.each {|k,v| req[k]=v}
    Net::HTTP.start(u.host, u.port, use_ssl: u.scheme == 'https') { |http| http.request(req)}
end
end 

