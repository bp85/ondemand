module NginxStage
  # This generator stages and generates the per-user NGINX environment.
  class PunConfigGenerator < Generator
    desc 'Generate a new per-user nginx config and process'

    footer <<-EOF.gsub(/^ {4}/, '')
    Examples:
        To generate a per-user nginx environment & launch nginx:

            nginx_stage pun --user=bob --app-init-uri='/nginx/init?redir=$http_x_forwarded_escaped_uri'

        this will add a URI redirect if the user accesses an app that doesn't exist.

        To generate ONLY the per-user nginx environment:

            nginx_stage pun --user=bob --skip-nginx

        this will return the per-user nginx config path and won't run nginx. In addition
        it will remove the URI redirect from the config unless we specify `--app-init-uri`.
    EOF

    # Accepts `user` as an option and validates user
    add_user_support

    # Accepts `skip_nginx` as an option
    add_skip_nginx_support

    # @!method app_init_uri
    #   The app initialization URI the user is redirected to if can't find the
    #   app in the per-user NGINX config
    #   @return [String] app init redirect url
    add_option :app_init_uri do
      {
        opt_args: ["-a", "--app-init-uri=APP_INIT_URI", "# The user is redirected to the APP_INIT_URI if app doesn't exist"],
        default: nil,
        before_init: -> (uri) do
          raise InvalidAppInitUri, "invalid app-init-uri syntax: #{uri}" if uri =~ /[^-\w\/?$=&]/
          uri
        end
      }
    end

    # Create the user's personal per-user NGINX `/tmp` location for the various
    # nginx cache directories, and give ownership to user
    add_hook :create_user_tmp_root do
      empty_directory tmp_root
      FileUtils.chown user, group, tmp_root if Process.uid == 0
    end

    # Create the user's personal per-user NGINX `/log` location for the various
    # nginx log files (e.g., 'error.log' & 'access.log')
    add_hook :create_user_log_roots do
      empty_directory File.dirname(error_log_path)
      empty_directory File.dirname(access_log_path)
    end

    # Create per-user NGINX pid root
    add_hook :create_pid_root do
      empty_directory File.dirname(pid_path)
    end

    # Create and secure the nginx socket root. The socket file needs to be only
    # accessible by the reverse proxy user.
    add_hook :create_and_secure_socket_root do
      socket_root = File.dirname(socket_path)
      empty_directory socket_root
      FileUtils.chmod 0700, socket_root
      FileUtils.chown NginxStage.proxy_user, nil, socket_root if Process.uid == 0
    end

    # Generate the per-user NGINX config from the 'pun.conf.erb' template
    add_hook :create_config do
      template "pun.conf.erb", config_path
    end

    # Run the per-user NGINX process (exit quietly on success)
    add_hook :exec_nginx do
      if !skip_nginx
        o, s = Open3.capture2e([NginxStage.nginx_bin, "(#{user})"], *NginxStage.nginx_args(user: user))
        s.success? ? exit : abort(o)
      end
    end

    # If skip nginx, then output path to the generated per-user NGINX config
    add_hook :output_pun_config_path do
      puts config_path
    end


    private
      # per-user NGINX config path
      def config_path
        NginxStage.pun_config_path(user: user)
      end

      # Primary group of the user
      def group
        user.group
      end

      # Path to the user's personal error.log
      def error_log_path
        NginxStage.pun_error_log_path(user: user)
      end

      # Path to the user's personal access.log
      def access_log_path
        NginxStage.pun_access_log_path(user: user)
      end

      # Path to user's personal tmp root
      def tmp_root
        NginxStage.pun_tmp_root(user: user)
      end

      # Path to the user's per-user NGINX pid file
      def pid_path
        NginxStage.pun_pid_path(user: user)
      end

      # Path to the user's per-user NGINX socket file
      def socket_path
        NginxStage.pun_socket_path(user: user)
      end

      # Array of wildcard paths to app configs user has access to
      def app_configs
        NginxStage.pun_app_configs(user: user).map do |envmt|
          NginxStage.app_config_path envmt
        end
      end
  end
end
