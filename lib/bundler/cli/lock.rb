# frozen_string_literal: true

module Bundler
  class CLI::Lock
    attr_reader :options

    def initialize(options)
      @options = options
    end

    def run
      unless Bundler.default_gemfile
        Bundler.ui.error "Unable to find a Gemfile to lock"
        exit 1
      end

      check_for_conflicting_options

      print = options[:print]
      previous_output_stream = Bundler.ui.output_stream
      Bundler.ui.output_stream = :stderr if print

      Bundler::Fetcher.disable_endpoint = options["full-index"]

      update = options[:update]
      conservative = options[:conservative]
      bundler = options[:bundler]

      if update.is_a?(Array) # unlocking specific gems
        Bundler::CLI::Common.ensure_all_gems_in_lockfile!(update)
        update = { gems: update, conservative: conservative }
      elsif update && conservative
        update = { conservative: conservative }
      elsif update && bundler
        update = { bundler: bundler }
      end

      file = options[:lockfile]
      file = file ? Pathname.new(file).expand_path : Bundler.default_lockfile

      Bundler.settings.temporary(frozen: false) do
        definition = Bundler.definition(update, file)
        definition.add_checksums if options["add-checksums"]

        Bundler::CLI::Common.configure_gem_version_promoter(definition, options) if options[:update]

        options["remove-platform"].each do |platform_string|
          platform = Gem::Platform.new(platform_string)
          definition.remove_platform(platform)
        end

        options["add-platform"].each do |platform_string|
          platform = Gem::Platform.new(platform_string)
          if platform.to_s == "unknown"
            Bundler.ui.error "The platform `#{platform_string}` is unknown to RubyGems and can't be added to the lockfile."
            exit 1
          end
          definition.add_platform(platform)
        end

        if definition.platforms.empty?
          raise InvalidOption, "Removing all platforms from the bundle is not allowed"
        end

        definition.remotely! unless options[:local]

        if options["normalize-platforms"]
          definition.normalize_platforms
        end

        if print
          puts definition.to_lock
        else
          puts "Writing lockfile to #{file}"
          definition.lock
        end
      end

      Bundler.ui.output_stream = previous_output_stream
    end

    private

    def check_for_conflicting_options
      if options["normalize-platforms"] && options["add-platform"].any?
        raise InvalidOption, "--normalize-platforms can't be used with --add-platform"
      end

      if options["normalize-platforms"] && options["remove-platform"].any?
        raise InvalidOption, "--normalize-platforms can't be used with --remove-platform"
      end
    end
  end
end
