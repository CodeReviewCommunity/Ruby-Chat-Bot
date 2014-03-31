ACCESS_TOKEN = '<insert token>'
# get your access token here:
# https://stackexchange.com/oauth/dialog?client_id=2666&redirect_uri=http://keyboardfire.com/chatdump.html&scope=no_expiry
$root = 'http://stackexchange.com'
$chatroot = 'http://chat.stackexchange.com'
$room_number = 12723
site = 'codereview'
email = '<insert email>'
password = '<insert password>'
$ERRCOUNT = 0

require 'rubygems'
require 'mechanize'
require 'logger'
require 'faye/websocket'
require 'eventmachine'
require 'json'
require 'cgi'
require 'net/http'

loop {
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
  loop {
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

send_message $ERR ? "An unknown error occurred. Restarting." : "Initialized."

last_date = 0
if site
loop {
  uri = URI.parse "https://api.stackexchange.com/2.2/events?pagesize=100&since=#{last_date}&site=#{site}&filter=!9WgJfejF6&key=thqRkHjZhayoReI9ARAODA((&access_token=#{ACCESS_TOKEN}"
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  data = JSON.parse http.get(uri.request_uri).body
  puts(data)
  events = data['items']
  
  data['items'].each do |event|
    last_date = [last_date, event['creation_date'].to_i + 1].max
    if ['answer_posted'].include? event['event_type']
      send_message "New answer detected:"
      send_message event['link']
      puts "Answer posted."
    end
  end
  puts "#{data['quota_remaining']}/#{data['quota_max']} quota remaining"
  sleep(40 + (data['backoff'] || 0).to_i) # add backoff time if any, just in case
}

else

  actions = {
    '196-answers-newest' => ->data{
      title = data['body'].match(/class="question-hyperlink">([^<]*)</)[1]
      tags = data['tags']
      url = 'http://codereview.stackexchange.com' + data['body'].match(/<a href="([^"]+)"/)[1] # CTHULHU

      triggers = []

      send_message "@syb0rg New answer detected:"
      sleep 0.5
      send_message url
      puts('Posted answer')
    },
    '198-answers-newest' => ->data{
      url = 'http://meta.codereview.stackexchange.com/' + data['body'].match(/<a href="([^"]+)"/)[1]

      send_message 'New meta answer detected:'
      sleep 0.5
      send_message url
      puts('Posted meta answer.')
    }
  }
  EM.run {
    ws = Faye::WebSocket::Client.new('ws://sockets.ny.stackexchange.com')

    ws.on :open do |event|
      actions.keys.each{|k| ws.send(k.dup) } # dup because hash keys are frozen
    end

    ws.on :message do |event|
      p event.data
      p Time.now.to_i
      msg = JSON.parse event.data
      puts(msg)
      if msg["action"] == 'hb'
        ws.send 'hb'
      else
        data = JSON.parse(msg['data']) rescue nil
        actions[msg["action"]][data] if data
      end
    end
  }

end
rescue Interrupt => e
  send_message 'Killed manually.'
  raise e
rescue => e
  $ERR = e
  $ERRCOUNT += 1
  p e
  p e.backtrace
  exit if $ERRCOUNT > 5
end
}
