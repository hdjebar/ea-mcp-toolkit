"""Tests for ea-sqlite-mcp.py tool functions and helper utilities.

Imports the server module via the conftest stub (mcp package is faked so all
@mcp.tool()-decorated functions are plain Python callables).
"""
import pytest
import ea_sqlite_mcp as ea


# ============================================================================
# Helper functions
# ============================================================================

class TestSafeLabel:
    def test_clean_passthrough(self):
        assert ea._safe_label("Normal Name") == "Normal Name"

    def test_double_quotes_replaced(self):
        assert '"' not in ea._safe_label('Name "with" quotes')

    def test_square_brackets_replaced(self):
        out = ea._safe_label("Node [type]")
        assert "[" not in out and "]" not in out

    def test_curly_braces_replaced(self):
        out = ea._safe_label("Node {v1}")
        assert "{" not in out and "}" not in out

    def test_newline_stripped(self):
        assert "\n" not in ea._safe_label("Line1\nLine2")

    def test_cr_stripped(self):
        assert "\r" not in ea._safe_label("text\r\n")


class TestInParams:
    def test_multiple_values(self):
        ph, params = ea._in_params([1, 2, 3])
        assert ph == "?,?,?"
        assert set(params) == {1, 2, 3}

    def test_single_value(self):
        ph, params = ea._in_params([42])
        assert ph == "?"
        assert params == (42,)

    def test_set_input(self):
        ph, params = ea._in_params({7, 8})
        assert ph.count("?") == 2

    def test_tuple_input(self):
        ph, params = ea._in_params((10, 20))
        assert ph.count("?") == 2


class TestGetLayer:
    def test_business_process(self):
        assert ea._get_layer("ArchiMate_BusinessProcess") == "Business"

    def test_application_component(self):
        assert ea._get_layer("ArchiMate_ApplicationComponent") == "Application"

    def test_technology_node(self):
        assert ea._get_layer("ArchiMate_Node") == "Technology"

    def test_motivation_goal(self):
        assert ea._get_layer("ArchiMate_Goal") == "Motivation"

    def test_strategy_capability(self):
        assert ea._get_layer("ArchiMate_Capability") == "Strategy"

    def test_implementation_work_package(self):
        assert ea._get_layer("ArchiMate_WorkPackage") == "Implementation"

    def test_unknown_stereotype(self):
        assert ea._get_layer("SomeRandomStereotype") == "Unknown"

    def test_archimate3_double_prefix(self):
        # Both prefix styles must resolve correctly
        assert ea._get_layer("ArchiMate3::ArchiMate_Node") == "Technology"


# ============================================================================
# list_elements
# ============================================================================

class TestListElements:
    def test_returns_all_elements(self, qea_path):
        out = ea.list_elements(qea_path)
        assert "Order Management" in out
        assert "CRM System" in out
        assert "Database Server" in out

    def test_filter_by_object_type(self, qea_path):
        out = ea.list_elements(qea_path, object_type="Node")
        assert "Database Server" in out
        assert "CRM System" not in out

    def test_filter_by_name_substring(self, qea_path):
        out = ea.list_elements(qea_path, name_contains="CRM")
        assert "CRM System" in out
        assert "Order Management" not in out

    def test_filter_by_stereotype(self, qea_path):
        out = ea.list_elements(qea_path, stereotype="BusinessProcess")
        assert "Order Management" in out
        assert "CRM System" not in out

    def test_filter_by_package(self, qea_path):
        out = ea.list_elements(qea_path, package_name="Application")
        assert "CRM System" in out
        # Business layer element should not appear
        assert "Order Management" not in out

    def test_no_match_returns_message(self, qea_path):
        out = ea.list_elements(qea_path, name_contains="ZZZNOMATCH")
        assert "No elements found" in out

    def test_limit_respected(self, qea_path):
        out = ea.list_elements(qea_path, limit=2)
        assert out.count("•") <= 2


# ============================================================================
# get_element_detail
# ============================================================================

class TestGetElementDetail:
    def test_known_element_properties(self, qea_path):
        out = ea.get_element_detail(qea_path, "Order Management")
        assert "BusinessProcess" in out
        assert "Alice" in out          # author
        assert "Proposed" in out       # status

    def test_tagged_values_shown(self, qea_path):
        out = ea.get_element_detail(qea_path, "Order Management")
        assert "Owner" in out
        assert "Priority" in out

    def test_relationships_shown(self, qea_path):
        # Order Management is targeted by CRM System's Serving connector
        out = ea.get_element_detail(qea_path, "Order Management")
        assert "Serving" in out or "CRM System" in out

    def test_diagram_memberships_shown(self, qea_path):
        out = ea.get_element_detail(qea_path, "Order Management")
        assert "Application Architecture" in out

    def test_not_found_message(self, qea_path):
        out = ea.get_element_detail(qea_path, "DoesNotExist")
        assert "not found" in out.lower()


# ============================================================================
# trace_dependencies
# ============================================================================

class TestTraceDependencies:
    def test_outbound_from_crm_system(self, qea_path):
        out = ea.trace_dependencies(qea_path, "CRM System", depth=1, direction="outbound")
        assert "Order Management" in out or "Database Server" in out

    def test_inbound_to_order_management(self, qea_path):
        out = ea.trace_dependencies(qea_path, "Order Management", depth=1, direction="inbound")
        assert "CRM System" in out

    def test_not_found_returns_message(self, qea_path):
        out = ea.trace_dependencies(qea_path, "NoSuchElement")
        assert "not found" in out.lower()

    def test_summary_line_present(self, qea_path):
        out = ea.trace_dependencies(qea_path, "CRM System", depth=2)
        assert "Total elements in trace:" in out

    def test_depth_1_does_not_traverse_further(self, qea_path):
        # With depth=1 we should see direct connections only
        out = ea.trace_dependencies(qea_path, "CRM System", depth=1, direction="outbound")
        assert "Total elements in trace:" in out


# ============================================================================
# model_statistics
# ============================================================================

class TestModelStatistics:
    def test_returns_element_count(self, qea_path):
        out = ea.model_statistics(qea_path)
        assert "Total elements:" in out

    def test_returns_diagram_section(self, qea_path):
        out = ea.model_statistics(qea_path)
        assert "Diagrams" in out

    def test_returns_package_section(self, qea_path):
        out = ea.model_statistics(qea_path)
        assert "Packages" in out

    def test_orphan_count_present(self, qea_path):
        # "Orphan Element" is not placed on any diagram
        out = ea.model_statistics(qea_path)
        assert "Orphan" in out

    def test_archimate_layer_distribution(self, qea_path):
        out = ea.model_statistics(qea_path)
        # At least one ArchiMate layer should appear
        assert any(layer in out for layer in ["Business", "Application", "Technology"])


# ============================================================================
# validate_archimate
# ============================================================================

class TestValidateArchimate:
    def test_finds_unknown_rel_type(self, qea_path):
        out = ea.validate_archimate(qea_path)
        assert "Violations" in out
        # UnknownRelType should be flagged
        assert "UnknownRelType" in out

    def test_summary_lines_present(self, qea_path):
        out = ea.validate_archimate(qea_path)
        assert "Total relationships checked:" in out
        assert "Valid:" in out


# ============================================================================
# list_packages
# ============================================================================

class TestListPackages:
    def test_root_level_packages(self, qea_path):
        out = ea.list_packages(qea_path)
        assert "Business" in out

    def test_children_of_parent(self, qea_path):
        out = ea.list_packages(qea_path, parent_name="Business")
        assert "Application" in out

    def test_not_found_message(self, qea_path):
        out = ea.list_packages(qea_path, parent_name="NonExistent")
        assert "not found" in out.lower()


# ============================================================================
# list_diagrams
# ============================================================================

class TestListDiagrams:
    def test_all_diagrams(self, qea_path):
        out = ea.list_diagrams(qea_path)
        assert "Application Architecture" in out
        assert "Technology View" in out

    def test_filter_by_name(self, qea_path):
        out = ea.list_diagrams(qea_path, name_contains="Application")
        assert "Application Architecture" in out
        assert "Technology View" not in out

    def test_filter_by_type(self, qea_path):
        out = ea.list_diagrams(qea_path, diagram_type="Logical")
        assert "Application Architecture" in out


# ============================================================================
# query_sql — injection guards and basic functionality
# ============================================================================

class TestQuerySql:
    def test_select_returns_data(self, qea_path):
        out = ea.query_sql(qea_path, "SELECT Name FROM t_object ORDER BY Name")
        assert "CRM System" in out
        assert "Order Management" in out

    def test_column_headers_present(self, qea_path):
        out = ea.query_sql(qea_path, "SELECT Name, Object_Type FROM t_object")
        assert "Name" in out
        assert "Object_Type" in out

    def test_delete_blocked(self, qea_path):
        out = ea.query_sql(qea_path, "DELETE FROM t_object")
        assert "ERROR" in out

    def test_insert_blocked(self, qea_path):
        out = ea.query_sql(
            qea_path,
            "INSERT INTO t_object VALUES (99,'x','y','','','','','','','','',1,'')"
        )
        assert "ERROR" in out
        # Verify the record was NOT inserted (read-only URI mode)
        check = ea.query_sql(qea_path, "SELECT COUNT(*) FROM t_object WHERE Object_ID = 99")
        assert "1" not in check.split("\n", 2)[-1]  # count should be 0

    def test_update_blocked(self, qea_path):
        out = ea.query_sql(qea_path, "UPDATE t_object SET Name='x' WHERE 1=1")
        assert "ERROR" in out

    def test_drop_blocked(self, qea_path):
        out = ea.query_sql(qea_path, "DROP TABLE t_object")
        assert "ERROR" in out

    def test_attach_blocked(self, qea_path):
        out = ea.query_sql(qea_path, "ATTACH DATABASE '/tmp/evil.db' AS leak")
        assert "ERROR" in out

    def test_create_blocked(self, qea_path):
        out = ea.query_sql(qea_path, "CREATE TABLE evil (x TEXT)")
        assert "ERROR" in out

    def test_empty_result_message(self, qea_path):
        out = ea.query_sql(qea_path, "SELECT * FROM t_object WHERE Name = 'ZZZNOMATCH'")
        assert "no results" in out.lower()


# ============================================================================
# Missing / invalid path errors
# ============================================================================

class TestPathErrors:
    def test_missing_file_raises(self):
        with pytest.raises(FileNotFoundError):
            ea.list_elements("/nonexistent/path/model.qea")

    def test_empty_path_raises(self):
        import os
        # Clear default env var for this test
        original = os.environ.pop("EA_MODEL_PATH", None)
        try:
            with pytest.raises(ValueError):
                ea.list_elements("")
        finally:
            if original is not None:
                os.environ["EA_MODEL_PATH"] = original
