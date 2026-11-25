# frozen_string_literal: true

require "telegram/bot"
require "sqlite3"
require "uri"

HELP = <<~TEXT.strip
  Я зберігаю твої посилання за тегами.
  /save https://www.ruby-lang.org ruby — зберегти посилання
  /get ruby — показати посилання за тегом
TEXT

def valid_url?(url)
  uri = URI.parse(url)
  uri.is_a?(URI::HTTP) && !uri.host.to_s.empty? && uri.userinfo.nil?
rescue URI::InvalidURIError
  false
end

def valid_tag?(tag)
  /\A#?[\p{L}\p{N}_-]{1,64}\z/u.match?(tag)
end

def reply_to(db, user_id, text)
  command, *args = text.split
  case command
  when "/start", "/help"
    HELP
  when "/save"
    return "Формат команди: /save https://example.com тег" unless args.size == 2

    url, tag = args
    return "Введи повну адресу, що починається з http:// або https://." unless valid_url?(url)
    return "Тег має містити 1–64 літери, цифри, дефіс або підкреслення." unless valid_tag?(tag)

    tag = tag.delete_prefix("#").downcase
    db.execute("INSERT OR IGNORE INTO links (user_id, tag, url) VALUES (?, ?, ?)", [user_id, tag, url])
    db.changes.zero? ? "Це посилання вже є за тегом ##{tag}." : "Збережено за тегом ##{tag}."
  when "/get"
    return "Формат команди: /get тег" unless args.size == 1 && valid_tag?(args.first)

    tag = args.first.delete_prefix("#").downcase
    rows = db.execute("SELECT url FROM links WHERE user_id = ? AND tag = ? ORDER BY rowid", [user_id, tag])
    rows.empty? ? "За тегом ##{tag} ще немає посилань." : rows.flatten
  else
    "Список команд можна переглянути за допомогою /help."
  end
end

token = ENV["TELEGRAM_BOT_TOKEN"].to_s.strip
abort "Спочатку задай TELEGRAM_BOT_TOKEN у PowerShell (див. README.md)." if token.empty?

db = SQLite3::Database.new(File.join(__dir__, "links.sqlite3"))
db.busy_timeout(5000)
db.execute(<<~SQL)
  CREATE TABLE IF NOT EXISTS links (
    user_id INTEGER NOT NULL,
    tag TEXT NOT NULL,
    url TEXT NOT NULL,
    UNIQUE(user_id, tag, url)
  )
SQL

begin
  Telegram::Bot::Client.run(token) do |bot|
    bot.api.get_me
    puts "Підключено до Telegram. Відкрий особистий чат із ботом."
    bot.listen do |message|
      next unless message.is_a?(Telegram::Bot::Types::Message) && message.chat.type == "private"

      replies = reply_to(db, message.from.id, message.text.to_s)
      Array(replies).each do |reply|
        bot.api.send_message(chat_id: message.chat.id, text: reply)
      end
    end
  end
rescue Interrupt
  puts "Бота зупинено."
ensure
  db.close
end
