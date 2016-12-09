unit_tests do

  test "should respond to" do
      assert PRW.respond_to?(:thumbot_retry)
      assert PRW.respond_to?(:thumbot_merge)
      assert PRW.respond_to?(:run_thumbot_command)
      assert PRW.respond_to?(:contains_thumbot_command?)
      assert PRW.respond_to?(:parse_thumbot_command)
  end
  test "should be able to detect thumbot mention" do
    default_vcr_state do
      assert_false PRW.contains_thumbot_command?("this is a long comment with a reference to thumbot but no command")
    end
  end
  test "should be able to detect thumbot command" do
    default_vcr_state do
      assert_true PRW.contains_thumbot_command?("thumbot retry this is a long comment with a command ")
      assert_true PRW.contains_thumbot_command?("thumbot merge this is a long comment with a command ")
      assert_true PRW.contains_thumbot_command?("@thumbot merge this is a long comment with a command ")
      assert_false PRW.contains_thumbot_command?("comment with a command thumbot merge hidden in the text, which is unsupported")
      assert_false PRW.contains_thumbot_command?("this is a long comment with a command thumbot unrecognized_command")
    end
  end
  test "should be able to get thumbot_command from text" do
    default_vcr_state do
      assert_equal :retry, PRW.parse_thumbot_command("thumbot retry this is a long comment with a command")

    end
  end
  test "should be able to support thumbot_command with @" do
    default_vcr_state do
      assert_equal :retry, PRW.parse_thumbot_command("@thumbot retry yadayadayada")
      assert_equal :merge, PRW.parse_thumbot_command("@thumbot merge yadayadayada")
    end
  end
  test "should be able to run thumbot_command" do
    default_vcr_state do
      assert PRW.thumbot_retry
      assert_false PRW.thumbot_merge
    end
  end
end








