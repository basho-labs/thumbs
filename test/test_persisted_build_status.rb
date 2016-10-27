

unit_tests do

  test "should be able to read build status" do
   default_vcr_state do
    cassette(:load_pr) do
      prw=Thumbs::PullRequestWorker.new(:repo=>TESTREPO, :pr=>TESTPR)
      assert prw.build_status.key?(:steps)
      assert prw.build_status[:steps].key?(:merge)
      assert prw.build_status[:steps].keys.length == 1

      cassette(:read_build_status) do

        prw.run_build_steps

        status = prw.read_build_status
        repo=prw.repo.gsub(/\//, '_')
        file=File.join('/tmp/thumbs', "#{repo}_#{prw.most_recent_sha}.yml")

        parsed_file = File.exist?(file) ?  YAML.load(IO.read(file)) : nil
        assert parsed_file.keys.sort == status.keys.sort
        assert status.kind_of?(Hash)
        assert status.key?(:steps)
        assert status[:steps].key?(:merge)
        assert status[:steps].key?(:make), status[:steps].inspect
        assert status[:steps].key?(:make_test), status[:steps].inspect

        assert prw.build_status[:steps].keys.length == [:merge, :make, :make_test].length, prw.build_status[:steps].keys.inspect
      end
    end
   end

  end
  test "should be able to persist build status with utf8 and other bad characters" do
    default_vcr_state do
      cassette(:load_pr) do
        prw=Thumbs::PullRequestWorker.new(:repo=>TESTREPO, :pr=>TESTPR)
        prw.run_build_steps
        test_content=IO.read(File.join(File.dirname(__FILE__), "/data/test_utf8_build_status.txt"))
        prw.build_status[:steps][:make][:output] = test_content
        prw.persist_build_status
        status = prw.read_build_status
        assert_equal prw.build_status[:steps][:make], status[:steps][:make]
      end
    end
  end
  def sanitize_text(text)
    text.encode('UTF-8', 'UTF-8', :invalid => :replace, :undef => :replace)
  end
  test "should fix bad utf8 byte sequence" do
    bad_test_string="hi \255"
    assert_raise(ArgumentError) do
      test_split = bad_test_string.split(' ')
    end

    fixed_bad_test_string=sanitize_text(bad_test_string)
    test_split = fixed_bad_test_string.split(' ')
    default_vcr_state do
      cassette(:load_pr) do
        prw=Thumbs::PullRequestWorker.new(:repo=>TESTREPO, :pr=>TESTPR)
        prw.run_build_steps
        prw.build_status[:steps][:make][:output]=bad_test_string

        prw.persist_build_status
        fixed_persisted_bad_test_string = prw.read_build_status[:steps][:make][:output]
        assert_equal "hi �", fixed_persisted_bad_test_string
      end
    end

  end
end



