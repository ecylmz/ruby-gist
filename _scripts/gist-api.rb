#!/usr/bin/ruby
# encoding: utf-8


require "net/https"
require "uri"
require 'json'
require 'yaml'
require 'x/util/git'
include X::Util

username = Git.config(:login)

def fetch_gists_data
  uri = URI.parse("https://api.github.com/users/ecylmz/gists")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  request = Net::HTTP::Get.new(uri.request_uri)
  response = http.request(request)
  data = response.body
  gist_data = JSON.parse(data)
  gist_data
end

def fetch_label
  gist_data = fetch_gists_data
  gist_count = gist_data.size
  descriptions = Hash.new
  id_map = Hash.new
  gist_data.each do |gist|
    use_label = gist['description']
    description = use_label
    label_id = gist['id']
    label_id = label_id.to_i
    if use_label != '' and use_label != nil
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
config = YAML::parse( File.open( "../_config.yml" ) )
MAIN_PATH = config.transform['main_path']
Dir.chdir(MAIN_PATH)

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
    gist = Hash.new
    if id_map[label].size == 1
      gist["label"] = label
      gist["id"] = ids
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
    gists = Hash.new
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
