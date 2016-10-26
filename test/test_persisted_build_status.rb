
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

        status = prw.read_build_status(prw.repo, prw.most_recent_sha)
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
end

