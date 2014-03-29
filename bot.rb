ACCESS_TOKEN = '<insert key>'
# get your access token here:
# https://stackexchange.com/oauth/dialog?client_id=2666&redirect_uri=http://keyboardfire.com/chatdump.html&scope=no_expiry
$root = 'http://stackexchange.com'
$chatroot = 'http://chat.stackexchange.com'
$room_number = 12723
site = 'codereview'
email = '<insert email>'
password = '<insert password>'

require 'rubygems'
require 'mechanize'
require 'json'
require 'net/http'

loop
{
    begin

    $agent = Mechanize.new
    $agent.agent.http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    login_form = $agent.get('https://openid.stackexchange.com/account/login').forms.first
    login_form.email = email
    login_form.password = password
    $agent.submit login_form, login_form.buttons.first
    puts 'logged in with SE openid'

    meta_login_form = $agent.get($root + '/users/login').forms.last
    meta_login_form.openid_identifier = 'https://openid.stackexchange.com/'
    $agent.submit meta_login_form, meta_login_form.buttons.last
    puts 'logged in to root'

    chat_login_form = $agent.get('http://stackexchange.com/users/chat-login').forms.last
    $agent.submit chat_login_form, chat_login_form.buttons.last
    puts 'logged in to chat'

    $fkey = $agent.get($chatroot + '/chats/join/favorite').forms.last.fkey
    puts 'found fkey'

    def send_message text
        loop 
        {
            begin
            resp = $agent.post("#{$chatroot}/chats/#{$room_number}/messages/new", [['text', text], ['fkey', $fkey]]).body
            success = JSON.parse(resp)['id'] != nil
            return if success
            rescue Mechanize::ResponseCodeError => e
            puts "Error: #{e.inspect}"
            end
            puts 'sleeping'
            sleep 3
        }
    end

    puts $ERR ? "An unknown error occurred. Bot restarted." : "Bot initialized."

    last_date = 0
    loop 
    {
        uri = URI.parse "https://api.stackexchange.com/2.2/events?pagesize=100&since=#{last_date}&site=#{site}&filter=!9WgJfejF6&key=thqRkHjZhayoReI9ARAODA((&access_token=#{ACCESS_TOKEN}"
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        data = JSON.parse http.get(uri.request_uri).body
        events = data['items']

        data['items'].each do |event|
            last_date = [last_date, event['creation_date'].to_i + 1].max
            if ['answer_posted'].include? event['event_type']
                send_message "[tag:rob0t] New answer detected:"
                send_message event['link']
                puts "Answer posted."
            end
        end
        puts "#{data['quota_remaining']}/#{data['quota_max']} quota remaining"
        sleep(40 + (data['backoff'] || 0).to_i) # add backoff time if any, just in case
    }

    rescue => e
        $ERR = e
        p e
    end
}
