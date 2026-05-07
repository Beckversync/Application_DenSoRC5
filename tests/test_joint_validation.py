from app.validation.joints import parse_six_joint_values, validate_manual_joint_values


def test_parse_six_joint_values_accepts_numbers_and_numeric_strings():
    ok, joints, reason = parse_six_joint_values([0, "1.5", -2, 3, 4, 5])

    assert ok is True
    assert joints == [0.0, 1.5, -2.0, 3.0, 4.0, 5.0]
    assert reason == "OK"


def test_parse_six_joint_values_rejects_wrong_length():
    ok, joints, reason = parse_six_joint_values([1, 2, 3])

    assert ok is False
    assert joints is None
    assert "6 values" in reason


def test_parse_six_joint_values_rejects_non_numeric_values():
    ok, joints, reason = parse_six_joint_values([1, 2, 3, 4, 5, "bad"])

    assert ok is False
    assert joints is None
    assert "non-numeric" in reason


def test_validate_manual_joint_values_rejects_out_of_range_joint():
    ok, reason = validate_manual_joint_values([0, 0, 0, 0, 0, 181], {})

    assert ok is False
    assert "out of configured range" in reason


def test_validate_manual_joint_values_rejects_non_numeric_step():
    ok, reason = validate_manual_joint_values([0, 0, 0, 0, 0, 0], {"stepDeg": "bad"})

    assert ok is False
    assert "stepDeg must be numeric" in reason


def test_validate_manual_joint_values_rejects_large_step():
    ok, reason = validate_manual_joint_values([0, 0, 0, 0, 0, 0], {"stepDeg": 99})

    assert ok is False
    assert "stepDeg must be <=" in reason
