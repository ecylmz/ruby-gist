#!/usr/bin/ruby
# encoding: utf-8


require 'net/https'
require 'uri'
require 'json'
require 'yaml'
require 'erb'
require 'x/util/git'
include X::Util

USERNAME = Git.config(:login)

def fetch_gists_data
  uri = URI.parse("https://api.github.com/users/#{USERNAME}/gists")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  request = Net::HTTP::Get.new(uri.request_uri)
  response = http.request(request)
  gist_data = JSON.parse(response.body)
  gist_data
end

def fetch_label
  gist_data = fetch_gists_data
  descriptions = Hash.new
  id_map = Hash.new
  gist_data.each do |gist|
    use_label = gist['description']
    description = use_label
    label_id = gist['id'].to_i
    if use_label != '' and !use_label.nil?
      labels = use_label[/.*\[([^\]]*)/,1].split
      labels.each do |label|
        unless id_map.include? label
          id_map[label] = Array.new
        end
        id_map[label] << label_id
        descriptions[label_id] = description
      end
    end
  end
  {:id_map => id_map, :descriptions => descriptions}
end

LABEL_DATA = fetch_label
if !File.exist? "../_config.yml"
  raise IOError.new "../_config.yml dosyası olmadan devam edilemez."
else
  config = YAML::parse( File.open( "../_config.yml" ) )
  if config.transform['main_path'].nil?
    raise NameError.new "_config.yml dosyasında main_path tanımlanmamış."
  else
    MAIN_PATH = config.transform['main_path']
    if !File.exist? MAIN_PATH
      raise IOError.new "#{MAIN_PATH} dizini olmadan devam edilemez."
    else
      Dir.chdir(MAIN_PATH)
    end
  end
end

def git_submodule
  id_map = LABEL_DATA[:id_map]
  `git checkout master`
  id_map.each_pair do |label,ids|
    ids.each do |id|
      `git submodule add git://gist.github.com/#{id}.git #{id}`
    end
  end
  `git commit -a -m "güncellendi."`
end

def sub_page
  template = ERB.new File.read(MAIN_PATH + "/_scripts/templates/sub_template.erb")
  gists = Array.new
  id_map = LABEL_DATA[:id_map]
  description = LABEL_DATA[:descriptions]
  id_map.each_key do |label|
    if !File.exist?(MAIN_PATH + label) then Dir.mkdir(label) end
  end
  id_map.each_pair do |label, ids|
    Dir.chdir(MAIN_PATH + label)
    #gist = Hash.new
    if id_map[label].size == 1
      gist = Hash.new
      gist["label"] = label
      gist["id"] = ids.first
      gist["description"] = description[ids]
      gists << gist
    else
      ids.each do |id|
        gist = Hash.new
        gist["label"] = label
        gist["id"] = id
        gist["description"] = description[id]
        gists << gist
      end
    end
    content = template.result(binding)
    file = File.open("index.html","w")
    file.puts content
    file.close
    gists = Array.new
    `git add index.html`
    `git commit -a -m "güncellendi"`
  end
end

def main_page
  `git checkout gh-pages`
  template = ERB.new File.read(MAIN_PATH + "/_scripts/templates/main_template.erb")
  gists = Array.new
  id_map = LABEL_DATA[:id_map]
  id_map.each_pair do |label, ids|
    gist = Hash.new
    gist["label"] = label
    gist["sum_label"] = ids.size
    gists << gist
  end
  content = template.result(binding)
  file = File.open("index.html","w")
  file.puts content
  file.close
  `git add index.html`
  `git commit -a -m "güncellendi"`
  sub_page
end

git_submodule
main_page
