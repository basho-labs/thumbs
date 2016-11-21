unit_tests do
  test "can run command in shell" do
    default_vcr_state do
      PRW.respond_to?(:run_command_in_shell)
      output, exit_code= PRW.run_command_in_shell("echo 0")
      assert_equal 0, output.strip.to_i
      assert_equal 0, exit_code
    end
  end
  test "can run command in docker" do
    docker_test_command="grep docker /proc/1/cgroup"
    cassette(:get_commits, :record => :new_episodes) do
      cassette(:run_docker, :record => :all) do

        PRW.try_merge
        unless ENV['_system_version']
          output, exit_code= PRW.run_command_in_shell(docker_test_command)
          assert_equal "", output
          assert 0 != exit_code
        end

        cassette(:run_docker_command1, :record => :all) do

          PRW.respond_to?(:run_command_in_docker)
          output, exit_code= PRW.run_command_in_docker(docker_test_command)
          assert output =~ /systemd\:\/docker\//
          assert_equal 0, exit_code
        end
      end

    end
  end


  test "can detect docker in config and run command in docker." do
    docker_test_command="grep docker /proc/1/cgroup"

    cassette(:run_docker_command, :record => :all) do
      cassette(:run_docker_command1, :record => :all) do

        PRW.try_merge

        PRW.thumb_config['docker']=false
        unless ENV['_system_version']
          output, exit_code = PRW.run_command(docker_test_command)
          assert_equal "", output
          assert 0 != exit_code
        end

        PRW.thumb_config['docker']=true

        output, exit_code= PRW.run_command(docker_test_command)
        assert output =~ /systemd\:\/docker\//, output
        assert_equal 0, exit_code
      end

    end
  end
end

