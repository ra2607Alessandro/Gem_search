namespace :smoke do 
    desc "Hit /up and expect ok"
    task :health => :environment do
        require 'net/http'
        uri= URI(ENV['URL'].presence || 'http://localhost:3000/up')
        req= Net::HTTP::Get.new(uri)
        req['X-Request-ID']= SecureRandom.uuid
        res= Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') {|h| h.request(req)}
        abort("smoke failed") unless res.is_a?(Net::HTTPSuccess) && res.body.include?('ok')
        puts "smoke ok"
    end
end
