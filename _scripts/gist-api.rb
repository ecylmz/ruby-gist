#!/usr/bin/ruby
# encoding: utf-8


require 'net/https'
require 'uri'
require 'json'
require 'yaml'
require 'erb'
require 'fileutils'

AUTO_COMMIT_MESSAGE = 'güncellendi.'
TEMPLATES_DIR = '_templates'
CONFIG_FILE = '_config.yml'

def get_username
  value = ENV["GITHUB_USER"]
  value =  %x(git config --global --get github.user1 2>/dev/null).chomp if value.nil? || value.empty?
  value
end

def get_template(template)
  ERB.new File.read(File.join(MAIN_PATH, TEMPLATES_DIR, template + '.erb'))
end

def emit_page(template, binding)
  content = get_template(template).result(binding)
  outfile = 'index.html'
  File.open(outfile, "w") { |f| f.puts content }
  `git add #{outfile}`
  `git commit -a -m #{AUTO_COMMIT_MESSAGE}`
end

def fetch_gists_data
  uri = URI.parse("https://api.github.com/users/#{get_username}/gists")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  request = Net::HTTP::Get.new(uri.request_uri)
  response = http.request(request)
  JSON.parse(response.body)
end

def load_label_data
  gist_data = fetch_gists_data
  id_map, descriptions = {}, {}
  gist_data.each do |gist|
    description = gist['description']
    if description != '' and !description.nil?
      description[/.*\[([^\]]*)/, 1].split.each do |label|
        label, id = *[label, gist['id']].map(&:to_sym)
        id_map[label] = [] unless id_map.include? label
        id_map[label] << id
        descriptions[id] = description
      end
    end
  end
  {:id_map => id_map, :descriptions => descriptions}
end

def git_submodule(label_data)
  `git checkout master`
  label_data[:id_map].values.flatten.uniq do |id|
  `git submodule add git://gist.github.com/#{id}.git #{id}`
  end
  `git commit -a -m #{AUTO_COMMIT_MESSAGE}`
end

def sub_page(label_data)
  gists = []
  label_data[:id_map].each do |label, ids|
    Dir.mkdir(label.to_s) unless File.exist? label.to_s
    FileUtils.chdir(label.to_s) do
      gists = ids.collect do |id|
        { :id => id, :label => label, :description => label_data[:descriptions][id] }
      end
      emit_page('sub_page', binding)
    end
  end
end

def main_page(label_data)
  `git checkout gh-pages`
  gists = label_data[:id_map].collect do |label, ids|
    { :label => label, :sum_label => ids.size }
  end
  emit_page('main_page', binding)
  sub_page(label_data)
end

if get_username.empty? || get_username.nil?
  $stderr.puts "Github kullanıcı adı tanımlı değil"
  exit(1)
end

if ! File.exist? CONFIG_FILE
  $stderr.puts "Bu betiği tepe dizinde çalıştırmalısınız"
  exit(1)
end
config = YAML::parse(File.open(CONFIG_FILE))

MAIN_PATH = config.transform['main_path']
if MAIN_PATH.nil? or MAIN_PATH.empty?
  $stderr.puts "Yerel Gist dizini tanımlanmamış"
  exit(1)
elsif ! File.directory? MAIN_PATH
  $stderr.puts "Yerel Gist dizini '#{MAIN_PATH}' bulunamadı"
  exit(1)
end

label_data = load_label_data
FileUtils.chdir(MAIN_PATH) do
  git_submodule(label_data)
  main_page(label_data)
end
