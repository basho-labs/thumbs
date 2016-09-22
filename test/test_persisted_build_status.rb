$:.unshift(File.join(File.dirname(__FILE__)))
require 'test_helper'


unit_tests do

  test "should be able to read build status" do
    # can get build status from build status persistence
    cassette(:load_pr) do
      prw=Thumbs::PullRequestWorker.new(:repo=>TESTREPO, :pr=>TESTPR)
      assert prw.build_status.key?(:steps)
      assert prw.build_status[:steps].key?(:merge)
      assert prw.build_status[:steps].keys.length == 1

      prw.run_build_steps

      cassette(:read_build_status) do

        status = prw.read_build_status(prw.repo, prw.pr.head.sha)
        assert status.kind_of?(Hash)
        assert status.key?(:steps)
        assert status[:steps].key?(:merge)
        assert status[:steps].key?(:make), status[:steps]
        assert status[:steps].key?(:make_test), status[:steps]

        assert prw.build_status[:steps].keys.length == [:merge, :make, :make_test].length

      end

    end
  end
end

