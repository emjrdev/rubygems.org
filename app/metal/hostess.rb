class Hostess < Sinatra::Default
  set :app_file, __FILE__

  def serve(path, redirect = false)
    headers "Cache-Control" => "public, max-age=3"

    if Rails.env.development? || Rails.env.test?
      send_file(path)
    else
      if redirect
        redirect File.join("http://s3.amazonaws.com", VaultObject.current_bucket, request.path_info)
      else
        # Query S3
        result = VaultObject.value(request.path_info,
                                    :if_modified_since => env['HTTP_IF_MODIFIED_SINCE'],
                                    :if_none_match => env['HTTP_IF_NONE_MATCH'])

        # These should raise a 304 if either of them match
        if result.response['last-modified']
          last_modified(result.response['last-modified'])
        end

        if value = result.response['etag']
          response['ETag'] = value

          # Conditional GET check
          if etags = env['HTTP_IF_NONE_MATCH']
            etags = etags.split(/\s*,\s*/)
            halt 304 if etags.include?(value) || etags.include?('*')
          end
        end

        # If we got a 304 back, let's give it back to the client
        halt 304 if result.response.code == 304

        # Otherwise return the result back
        result
      end
    end
  end

  get "/specs.4.8.gz" do
    content_type('application/x-gzip')
    serve(current_path)
  end

  get "/latest_specs.4.8.gz" do
    content_type('application/x-gzip')
    serve(current_path)
  end

  get "/prerelease_specs.4.8.gz" do
    content_type('application/x-gzip')
    serve(current_path)
  end

  get "/quick/Marshal.4.8/*.gemspec.rz" do
    content_type('application/x-deflate')
    serve(current_path)
  end

  get "/Marshal.4.8.Z" do
    content_type('application/x-deflate')
    serve(current_path)
  end

  get "/gems/*.gem" do
    Delayed::Job.enqueue Download.new(:raw => params[:splat].to_s, :created_at => Time.zone.now) unless ENV['MAINTENANCE_MODE']
    serve(current_path, true)
  end

  ["/yaml",
   "/yaml.Z",
   "/Marshal.4.8",
   "/specs.4.8",
   "/latest_specs.4.8",
   "/prerelease_specs.4.8"].each do |old_index|
    get old_index do
      serve(current_path)
    end
  end

  def current_path
    @current_path ||= Gemcutter.server_path(request.env["PATH_INFO"])
  end
end
