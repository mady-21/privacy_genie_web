Rails.autoloaders.each do |autoloader|
  autoloader.inflector.inflect("openai" => "OpenAI")
end
