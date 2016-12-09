unit_tests do

  test "should be able to read build status" do
    default_vcr_state do
      cassette(:load_pr) do
        cassette(:read_build_status) do
          cassette(:get_commits_for_branch, :record => :new_episodes) do
            PRW.reset_build_status
            PRW.unpersist_build_status
            PRW.thumbs_config['build_steps'] = ["make", "make test"]
            PRW.run_build_steps
            PRW.try_merge
            PRW.persist_build_status
            status = PRW.read_build_status

            repo=PRW.repo.gsub(/\//, '_')
            file=File.join('/tmp/thumbs', "#{repo}_#{PRW.build_guid}.yml")

            parsed_file = File.exist?(file) ? YAML.load(IO.read(file)) : nil
            assert parsed_file.keys.sort == status.keys.sort
            assert status.kind_of?(Hash)
            assert status.key?(:steps)
            assert status[:steps].key?(:merge)
            assert status[:steps].key?(:make), status[:steps].inspect
            assert status[:steps].key?(:make_test), status[:steps].inspect

            assert PRW.build_status[:steps].keys.length == [:merge, :make, :make_test].length, PRW.build_status[:steps].keys.inspect
          end
        end
      end
    end

  end
  test "should be able to persist build status with utf8 and other bad characters" do
    default_vcr_state do
      cassette(:load_pr) do
        cassette(:get_events_reload, :record => :new_episodes) do
          cassette(:get_events_reload2, :record => :new_episodes) do

            PRW.run_build_steps
            test_content=IO.read(File.join(File.dirname(__FILE__), "/data/test_utf8_build_status.txt"))
            PRW.build_status[:steps][:make][:output] = test_content
            PRW.persist_build_status
            status = PRW.read_build_status
            assert_equal PRW.build_status[:steps][:make], status[:steps][:make]
          end
        end
      end
    end
  end

  test "should be able to persist build status with a ref containing slashes" do
    default_vcr_state do
      cassette(:load_pr) do
        cassette(:get_events_reload, :record => :new_episodes) do
          cassette(:get_events_reload2, :record => :new_episodes) do
            PRW.thumbs_config['build_steps'] = ["make"]
            PRW.run_build_steps
            PRW.persist_build_status
            status = PRW.read_build_status
            assert_equal PRW.build_status[:steps][:make], status[:steps][:make]
          end
        end
      end
    end
  end

  def sanitize_text(text)
    text.encode('UTF-8', 'UTF-8', :invalid => :replace, :undef => :replace)
  end

  test "should fix bad utf8 byte sequence" do
    bad_test_string="hi \255"
    assert_raise(ArgumentError) do
      bad_test_string.split(' ')
    end

    fixed_bad_test_string=sanitize_text(bad_test_string)
    fixed_bad_test_string.split(' ')
    default_vcr_state do
      cassette(:load_pr) do
        cassette(:get_events_reload, :record => :new_episodes) do
          PRW.thumbs_config['build_steps'] = ["make"]
          PRW.run_build_steps
          PRW.build_status[:steps][:make][:output]=bad_test_string

          PRW.persist_build_status

          fixed_persisted_bad_test_string = PRW.read_build_status[:steps][:make][:output]
          assert_equal "hi �", fixed_persisted_bad_test_string
        end
      end
    end

  end
end



