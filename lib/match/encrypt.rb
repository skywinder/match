module Match
  class Encrypt
    require 'security'

    def server_name(git_url)
      ["match", git_url].join("_")
    end

    def password(git_url)
      password ||= ENV["MATCH_PASSWORD"]
      unless password
        item = Security::InternetPassword.find(server: server_name(git_url))
        password = item.password if item
      end

      unless password
        UI.important "Enter the passphrase that should be used to encrypt/decrypt your certificates"
        UI.important "This passphrase is specific per repository and will be stored in your local keychain"
        UI.important "Make sure to remember the password, as you'll need it when you run match on a different machine"
        while password.to_s.length == 0
          password = ask("Passphrase for Git Repo: ".yellow) { |q| q.echo = "*" }
        end
        Security::InternetPassword.add(server_name(git_url), "", password)
      end

      return @password
    end

    # removes the password from the keychain again
    def clear_password(git_url)
      Security::InternetPassword.delete(server: server_name(git_url))
    end

    def encrypt_repo(path: nil, git_url: nil)
      iterate(path) do |current|
        crypt(path: current,
          password: password(git_url),
            encrypt: true)
        UI.success "🔒  Encrypted '#{File.basename(current)}'" if $verbose
      end
      UI.success "🔒  Successfully encrypted certificates repo"
    end

    def decrypt_repo(path: nil, git_url: nil)
      iterate(path) do |current|
        begin
          crypt(path: current,
            password: password(git_url),
             encrypt: false)
        rescue
          UI.error "Couldn't decrypt the repo, please make sure you enter the right password!"
          clear_password(git_url)
          decrypt_repo(path: path, git_url: git_url)
          return
        end
        UI.success "🔓  Decrypted '#{File.basename(current)}'" if $verbose
      end
      UI.success "🔓  Successfully decrypted certificates repo"
    end

    private

    def iterate(source_path)
      Dir[File.join(source_path, "**", "*.{cer,p12,mobileprovision}")].each do |path|
        next if File.directory?(path)
        yield(path)
      end
    end

    def crypt(path: nil, password: nil, encrypt: true)
      tmpfile = File.join(Dir.mktmpdir, "temporary")
      command = ["openssl aes-256-cbc"]
      command << "-k \"#{password}\""
      command << "-in \"#{path}\""
      command << "-out \"#{tmpfile}\""
      command << "-a"
      command << "-d" unless encrypt
      command << "&> /dev/null" unless $verbose # to show show an error message is something goes wrong
      success = system(command.join(' '))
      raise "Error decrypting '#{path}'" unless success
      FileUtils.mv(tmpfile, path)
    end
  end
end
