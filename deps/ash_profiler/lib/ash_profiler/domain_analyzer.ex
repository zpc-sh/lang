defmodule AshProfiler.DomainAnalyzer do
  @moduledoc """
  Analyzes Ash domains and their resources for performance characteristics.
  """

  @doc """
  Analyzes a single Ash domain for DSL complexity and performance issues.
  """
  def analyze_domain(domain, opts \\ []) do
    resources = get_domain_resources(domain)
    
    %{
      domain: domain,
      resource_count: length(resources),
      total_complexity: calculate_total_complexity(resources),
      resources: Enum.map(resources, &analyze_resource(&1, opts)),
      bottlenecks: identify_bottlenecks(resources, opts),
      recommendations: generate_domain_recommendations(resources, opts)
    }
  end

  @doc """
  Analyzes a single Ash resource for DSL complexity.
  """
  def analyze_resource(resource, opts \\ []) do
    complexity = calculate_resource_complexity(resource)
    
    %{
      resource: resource,
      complexity: complexity,
      sections: analyze_dsl_sections(resource),
      issues: identify_resource_issues(resource, complexity, opts),
      optimizations: suggest_resource_optimizations(resource, complexity)
    }
  end

  # DSL Section Analysis
  defp analyze_dsl_sections(resource) do
    %{
      attributes: analyze_attributes_complexity(resource),
      relationships: analyze_relationships_complexity(resource),
      actions: analyze_actions_complexity(resource),
      policies: analyze_policies_complexity(resource),
      changes: analyze_changes_complexity(resource),
      preparations: analyze_preparations_complexity(resource),
      validations: analyze_validations_complexity(resource)
    }
  end

  defp analyze_attributes_complexity(resource) do
    attributes = get_resource_attributes(resource)
    
    base_count = length(attributes)
    computed_count = count_computed_attributes(attributes)
    constraint_complexity = sum_constraint_complexity(attributes)
    
    %{
      total: base_count + (computed_count * 3) + constraint_complexity,
      base_attributes: base_count,
      computed_attributes: computed_count,
      constraint_complexity: constraint_complexity
    }
  end

  defp analyze_relationships_complexity(resource) do
    relationships = get_resource_relationships(resource)
    
    base_count = length(relationships) * 2
    many_to_many_bonus = count_many_to_many_relationships(relationships) * 5
    through_relationship_bonus = count_through_relationships(relationships) * 3
    
    %{
      total: base_count + many_to_many_bonus + through_relationship_bonus,
      total_relationships: length(relationships),
      many_to_many_count: count_many_to_many_relationships(relationships),
      through_count: count_through_relationships(relationships)
    }
  end

  defp analyze_policies_complexity(resource) do
    policies = get_resource_policies(resource)
    
    base_count = length(policies) * 5
    expression_complexity = sum_policy_expression_complexity(policies)
    bypass_complexity = count_policy_bypasses(policies) * 2
    
    %{
      total: base_count + expression_complexity + bypass_complexity,
      policy_count: length(policies),
      expression_complexity: expression_complexity,
      bypass_count: count_policy_bypasses(policies)
    }
  end

  defp analyze_actions_complexity(resource) do
    actions = get_resource_actions(resource)
    
    base_count = length(actions)
    change_complexity = sum_action_changes_complexity(actions)
    validation_complexity = sum_action_validations_complexity(actions)
    
    %{
      total: base_count + change_complexity + validation_complexity,
      action_count: length(actions),
      change_complexity: change_complexity,
      validation_complexity: validation_complexity
    }
  end

  defp analyze_changes_complexity(resource) do
    changes = get_resource_changes(resource)
    %{
      total: length(changes) * 2,
      change_count: length(changes)
    }
  end

  defp analyze_preparations_complexity(resource) do
    preparations = get_resource_preparations(resource)
    %{
      total: length(preparations) * 2,
      preparation_count: length(preparations)
    }
  end

  defp analyze_validations_complexity(resource) do
    validations = get_resource_validations(resource)
    %{
      total: length(validations),
      validation_count: length(validations)
    }
  end

  # Resource introspection helpers
  defp get_resource_attributes(resource) do
    try do
      resource.attributes()
    rescue
      _ -> []
    end
  end

  defp get_resource_relationships(resource) do
    try do
      resource.relationships()
    rescue
      _ -> []
    end
  end

  defp get_resource_policies(resource) do
    try do
      resource.policies()
    rescue
      _ -> []
    end
  end

  defp get_resource_actions(resource) do
    try do
      resource.actions()
    rescue
      _ -> []
    end
  end

  defp get_resource_changes(resource) do
    try do
      resource.changes()
    rescue
      _ -> []
    end
  end

  defp get_resource_preparations(resource) do
    try do
      resource.preparations()
    rescue
      _ -> []
    end
  end

  defp get_resource_validations(resource) do
    try do
      resource.validations()
    rescue
      _ -> []
    end
  end

  defp get_domain_resources(domain) do
    try do
      domain.resources()
    rescue
      _ -> []
    end
  end

  # Complexity calculation helpers
  defp calculate_total_complexity(resources) do
    Enum.sum(Enum.map(resources, &calculate_resource_complexity(&1).total))
  end

  defp calculate_resource_complexity(resource) do
    sections = analyze_dsl_sections(resource)
    total = Enum.sum(Map.values(sections) |> Enum.map(& &1.total))
    
    %{
      total: total,
      breakdown: sections,
      severity: determine_severity(total)
    }
  end

  defp determine_severity(complexity) when complexity > 150, do: :critical
  defp determine_severity(complexity) when complexity > 100, do: :high
  defp determine_severity(complexity) when complexity > 50, do: :medium
  defp determine_severity(_), do: :low

  # Issue identification
  defp identify_resource_issues(resource, complexity, opts) do
    threshold = opts[:threshold] || 100
    issues = []
    
    # High overall complexity
    issues = if complexity.total > threshold do
      [%{
        type: :high_complexity,
        severity: :warning,
        message: "Resource complexity (#{complexity.total}) exceeds threshold (#{threshold})",
        resource: resource
      } | issues]
    else
      issues
    end
    
    # Policy complexity
    issues = if complexity.breakdown.policies.total > 50 do
      [%{
        type: :complex_policies,
        severity: :error,
        message: "Policy complexity is very high (#{complexity.breakdown.policies.total})",
        resource: resource
      } | issues]
    else
      issues
    end
    
    # Many relationships
    issues = if complexity.breakdown.relationships.total_relationships > 10 do
      [%{
        type: :many_relationships,
        severity: :warning,
        message: "High relationship count (#{complexity.breakdown.relationships.total_relationships}) may slow compilation",
        resource: resource
      } | issues]
    else
      issues
    end
    
    issues
  end

  # Additional helper functions for complexity analysis...
  defp count_computed_attributes(attributes) do
    Enum.count(attributes, fn attr ->
      Map.get(attr, :generated?, false) || Map.has_key?(attr, :calculation)
    end)
  end

  defp sum_constraint_complexity(attributes) do
    Enum.sum(Enum.map(attributes, fn attr ->
      constraints = Map.get(attr, :constraints, [])
      length(constraints)
    end))
  end

  defp count_many_to_many_relationships(relationships) do
    Enum.count(relationships, &(&1.type == :many_to_many))
  end

  defp count_through_relationships(relationships) do
    Enum.count(relationships, fn rel ->
      Map.has_key?(rel, :through) && not is_nil(rel.through)
    end)
  end

  defp sum_policy_expression_complexity(policies) do
    Enum.sum(Enum.map(policies, &calculate_expression_complexity/1))
  end

  defp calculate_expression_complexity(policy) do
    # Analyze policy expression AST complexity
    expr_string = inspect(policy.condition)
    
    # Count operators and complexity indicators
    operator_count = length(Regex.scan(~r/\band\b|\bor\b|\bnot\b/i, expr_string))
    function_count = length(Regex.scan(~r/\w+\s*\(/i, expr_string))
    field_access_count = length(Regex.scan(~r/\.\w+/i, expr_string))
    
    operator_count * 2 + function_count + field_access_count
  end

  defp count_policy_bypasses(policies) do
    Enum.count(policies, fn policy ->
      String.contains?(inspect(policy), "bypass")
    end)
  end

  defp sum_action_changes_complexity(actions) do
    Enum.sum(Enum.map(actions, fn action ->
      changes = Map.get(action, :changes, [])
      length(changes)
    end))
  end

  defp sum_action_validations_complexity(actions) do
    Enum.sum(Enum.map(actions, fn action ->
      validations = Map.get(action, :validations, [])
      length(validations)
    end))
  end

  defp identify_bottlenecks(resources, opts) do
    threshold = opts[:threshold] || 100
    
    resources
    |> Enum.map(&analyze_resource(&1, opts))
    |> Enum.filter(&(&1.complexity.total > threshold))
    |> Enum.sort_by(&(&1.complexity.total), :desc)
    |> Enum.take(10)  # Top 10 most complex resources
  end

  defp generate_domain_recommendations(resources, _opts) do
    total_resources = length(resources)
    complex_resources = Enum.count(resources, fn resource ->
      calculate_resource_complexity(resource).total > 100
    end)
    
    recommendations = []
    
    recommendations = if complex_resources > total_resources * 0.3 do
      ["Consider splitting domain - #{complex_resources}/#{total_resources} resources are highly complex" | recommendations]
    else
      recommendations
    end
    
    recommendations
  end

  defp suggest_resource_optimizations(_resource, complexity) do
    optimizations = []
    
    # Policy optimizations
    optimizations = if complexity.breakdown.policies.total > 30 do
      [%{
        type: :simplify_policies,
        description: "Simplify authorization policies",
        impact: :high,
        suggestions: [
          "Extract complex expressions to computed attributes",
          "Use simpler authorize_if conditions",
          "Consider policy composition patterns"
        ]
      } | optimizations]
    else
      optimizations
    end
    
    # Relationship optimizations
    optimizations = if complexity.breakdown.relationships.total_relationships > 8 do
      [%{
        type: :reduce_relationships,
        description: "Consider reducing relationship complexity",
        impact: :medium,
        suggestions: [
          "Move some relationships to separate resources",
          "Use manual relationships for complex queries",
          "Consider data layer optimizations"
        ]
      } | optimizations]
    else
      optimizations
    end
    
    optimizations
  end
end