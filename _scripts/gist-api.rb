#!/usr/bin/ruby
# encoding: utf-8


require 'net/https'
require 'uri'
require 'json'
require 'yaml'
require 'erb'
require 'fileutils'
require 'x/util/git'
include X::Util

USERNAME = Git.config(:login)
AUTO_COMMIT_MESSAGE = 'güncellendi.'
TEMPLATES_DIR = '_templates'
CONFIG_FILE = '_config.yml'

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
  uri = URI.parse("https://api.github.com/users/#{USERNAME}/gists")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  request = Net::HTTP::Get.new(uri.request_uri)
  response = http.request(request)
  JSON.parse(response.body)
end

def load_label_data
  gist_data = fetch_gists_data
  id_map = {}, descriptions = {}
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
    Dir.mkdir(label) unless File.exist? label
    FileUtils.chdir(label) do
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

git_submodule
main_page
