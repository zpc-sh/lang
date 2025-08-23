defmodule LangWeb.Design.LangTheme do
  @moduledoc """
  LANG™ 2025 Universal Design System

  This module defines the complete color palette, typography, spacing, and design tokens
  for the LANG Universal Text Intelligence Platform. It's designed to be reusable
  across multiple projects while maintaining consistency.

  ## Usage

      # Get CSS custom properties
      LangTheme.css_variables()

      # Get specific color
      LangTheme.color(:lang_primary)

      # Get color palette for UI
      LangTheme.color_palette()

      # Get Tailwind configuration
      LangTheme.tailwind_config()
  """

  # NOCSI Foundation Colors
  @nocsi_colors %{
    void: "#000000",
    deep: "#020202",
    dark: "#0a0a0a",
    carbon: "#111111",
    graphite: "#1a1a1a"
  }

  # LANG Primary Spectrum
  @lang_primary %{
    primary: "#4a9eff",
    primary_dark: "#0066ff",
    primary_glow: "#6eb3ff",
    primary_deep: "#0044cc",
    primary_void: "#002266"
  }

  # Semantic Intelligence Colors
  @semantic_colors %{
    parse: "#00ff88",
    parse_glow: "#33ffaa",
    parse_deep: "#00cc66",
    semantic: "#ff00ff",
    semantic_glow: "#ff66ff",
    semantic_deep: "#cc00cc",
    transform: "#00ffff",
    transform_glow: "#66ffff",
    transform_deep: "#00cccc"
  }

  # System State Colors
  @state_colors %{
    error: "#ff0066",
    error_glow: "#ff3388",
    warning: "#ffaa00",
    warning_glow: "#ffcc33",
    success: "#00ff66",
    info: "#00aaff"
  }

  # Text Hierarchy
  @text_colors %{
    primary: "#ffffff",
    secondary: "#e0e0e0",
    muted: "#888888",
    dimmed: "#666666",
    ghost: "#444444"
  }

  # Border & Surface Colors
  @surface_colors %{
    border_subtle: "#1a1a1a",
    border_default: "#222222",
    border_strong: "#333333",
    border_glow: "rgba(74, 158, 255, 0.3)"
  }

  # Design System Gradients
  @gradients %{
    primary: "linear-gradient(135deg, #4a9eff 0%, #0066ff 100%)",
    parse: "linear-gradient(135deg, #00ff88 0%, #00cc66 100%)",
    semantic: "linear-gradient(135deg, #ff00ff 0%, #cc00cc 100%)",
    aurora: "linear-gradient(135deg, #4a9eff 0%, #00ff88 33%, #ff00ff 66%, #00ffff 100%)",
    void: "linear-gradient(180deg, #0a0a0a 0%, #000000 100%)"
  }

  # Shadow System
  @shadows %{
    sm: "0 2px 4px rgba(0, 0, 0, 0.5)",
    md: "0 4px 8px rgba(0, 0, 0, 0.5)",
    lg: "0 8px 16px rgba(0, 0, 0, 0.5)",
    glow: "0 0 30px rgba(74, 158, 255, 0.3)"
  }

  # Typography Scale
  @typography %{
    font_display: "'SF Pro Display', -apple-system, BlinkMacSystemFont, sans-serif",
    font_body: "'SF Pro Text', -apple-system, BlinkMacSystemFont, sans-serif",
    font_mono: "'SF Mono', 'Fira Code', 'Monaco', monospace"
  }

  # Spacing Scale (matches CSS --space-* variables)
  @spacing %{
    xs: "4px",
    sm: "8px",
    md: "16px",
    lg: "24px",
    xl: "32px",
    "2xl": "48px",
    "3xl": "64px",
    "4xl": "96px",
    "5xl": "128px"
  }

  # Animation Curves
  @animations %{
    smooth: "cubic-bezier(0.4, 0, 0.2, 1)",
    bounce: "cubic-bezier(0.68, -0.55, 0.265, 1.55)",
    elastic: "cubic-bezier(0.175, 0.885, 0.32, 1.275)"
  }

  @doc """
  Returns all colors combined into a single map
  """
  def all_colors do
    Map.merge(@nocsi_colors, @lang_primary)
    |> Map.merge(@semantic_colors)
    |> Map.merge(@state_colors)
    |> Map.merge(@text_colors)
    |> Map.merge(@surface_colors)
  end

  @doc """
  Gets a specific color by atom key
  """
  def color(key) when is_atom(key) do
    all_colors()[key]
  end

  @doc """
  Gets a color by string key
  """
  def color(key) when is_binary(key) do
    all_colors()[String.to_atom(key)]
  end

  @doc """
  Returns the NOCSI foundation color palette
  """
  def nocsi_colors, do: @nocsi_colors

  @doc """
  Returns the LANG primary color spectrum
  """
  def lang_colors, do: @lang_primary

  @doc """
  Returns semantic intelligence colors
  """
  def semantic_colors, do: @semantic_colors

  @doc """
  Returns system state colors
  """
  def state_colors, do: @state_colors

  @doc """
  Returns text hierarchy colors
  """
  def text_colors, do: @text_colors

  @doc """
  Returns surface and border colors
  """
  def surface_colors, do: @surface_colors

  @doc """
  Returns design system gradients
  """
  def gradients, do: @gradients

  @doc """
  Returns shadow definitions
  """
  def shadows, do: @shadows

  @doc """
  Returns typography definitions
  """
  def typography, do: @typography

  @doc """
  Returns spacing scale
  """
  def spacing, do: @spacing

  @doc """
  Returns animation curves
  """
  def animations, do: @animations

  @doc """
  Generates CSS custom properties for the entire design system
  """
  def css_variables do
    nocsi_vars = generate_css_vars(@nocsi_colors, "nocsi")
    lang_vars = generate_css_vars(@lang_primary, "lang")
    semantic_vars = generate_css_vars(@semantic_colors, "lang")
    state_vars = generate_css_vars(@state_colors, "lang")
    text_vars = generate_css_vars(@text_colors, "lang-text")
    surface_vars = generate_css_vars(@surface_colors, "lang")
    gradient_vars = generate_css_vars(@gradients, "lang-gradient")
    shadow_vars = generate_css_vars(@shadows, "lang-shadow")
    type_vars = generate_css_vars(@typography, "font")
    spacing_vars = generate_css_vars(@spacing, "space")
    animation_vars = generate_css_vars(@animations, "ease")

    """
    :root {
      /* NOCSI Brand Colors */
    #{nocsi_vars}

      /* LANG Primary Spectrum */
    #{lang_vars}

      /* Semantic Intelligence Colors */
    #{semantic_vars}

      /* State Colors */
    #{state_vars}

      /* Text Hierarchy */
    #{text_vars}

      /* Borders & Surfaces */
    #{surface_vars}

      /* Gradients */
    #{gradient_vars}

      /* Shadows */
    #{shadow_vars}

      /* Typography Scale */
    #{type_vars}

      /* Spacing Scale */
    #{spacing_vars}

      /* Animation Curves */
    #{animation_vars}
    }
    """
  end

  @doc """
  Generates Tailwind CSS configuration for the design system
  """
  def tailwind_config do
    %{
      theme: %{
        extend: %{
          colors: %{
            nocsi: color_map_to_tailwind(@nocsi_colors),
            lang: color_map_to_tailwind(@lang_primary),
            semantic: color_map_to_tailwind(@semantic_colors),
            state: color_map_to_tailwind(@state_colors)
          },
          fontFamily: %{
            display: ["'SF Pro Display'", "-apple-system", "BlinkMacSystemFont", "sans-serif"],
            body: ["'SF Pro Text'", "-apple-system", "BlinkMacSystemFont", "sans-serif"],
            mono: ["'SF Mono'", "'Fira Code'", "Monaco", "monospace"]
          },
          spacing: spacing_map_to_tailwind(@spacing),
          boxShadow: shadow_map_to_tailwind(@shadows),
          transitionTimingFunction: animation_map_to_tailwind(@animations)
        }
      }
    }
  end

  @doc """
  Returns a structured color palette for UI components
  """
  def color_palette do
    %{
      foundation: format_color_section("NOCSI Foundation", @nocsi_colors),
      primary: format_color_section("LANG Primary", @lang_primary),
      semantic: format_color_section("Semantic Intelligence", @semantic_colors),
      state: format_color_section("System States", @state_colors),
      text: format_color_section("Text Hierarchy", @text_colors),
      surface: format_color_section("Surfaces", @surface_colors)
    }
  end

  @doc """
  Returns semantic color variants for specific use cases
  """
  def semantic_variants do
    %{
      parse: %{
        base: @semantic_colors.parse,
        glow: @semantic_colors.parse_glow,
        deep: @semantic_colors.parse_deep,
        variants: ["#33ffaa", "#00cc66", "#009944"]
      },
      semantic: %{
        base: @semantic_colors.semantic,
        glow: @semantic_colors.semantic_glow,
        deep: @semantic_colors.semantic_deep,
        variants: ["#ff66ff", "#cc00cc", "#990099"]
      },
      transform: %{
        base: @semantic_colors.transform,
        glow: @semantic_colors.transform_glow,
        deep: @semantic_colors.transform_deep,
        variants: ["#66ffff", "#00cccc", "#009999"]
      }
    }
  end

  @doc """
  Generates component-specific theme configurations
  """
  def component_themes do
    %{
      button: %{
        primary: %{
          background: @gradients.primary,
          hover: @lang_primary.primary_dark,
          text: @text_colors.primary
        },
        secondary: %{
          background: @surface_colors.border_strong,
          hover: @surface_colors.border_default,
          text: @text_colors.secondary
        },
        parse: %{
          background: @gradients.parse,
          hover: @semantic_colors.parse_deep,
          text: @nocsi_colors.void
        },
        semantic: %{
          background: @gradients.semantic,
          hover: @semantic_colors.semantic_deep,
          text: @text_colors.primary
        }
      },
      card: %{
        background: @nocsi_colors.carbon,
        border: @surface_colors.border_default,
        hover_border: @surface_colors.border_glow,
        shadow: @shadows.md
      },
      intelligence: %{
        parse: %{
          accent: @semantic_colors.parse,
          background: @nocsi_colors.graphite,
          glow: @semantic_colors.parse_glow
        },
        semantic: %{
          accent: @semantic_colors.semantic,
          background: @nocsi_colors.graphite,
          glow: @semantic_colors.semantic_glow
        },
        transform: %{
          accent: @semantic_colors.transform,
          background: @nocsi_colors.graphite,
          glow: @semantic_colors.transform_glow
        }
      }
    }
  end

  # Private helper functions

  defp generate_css_vars(map, prefix) when is_map(map) do
    map
    |> Enum.map(fn {key, value} ->
      css_key = key |> Atom.to_string() |> String.replace("_", "-")
      "  --#{prefix}-#{css_key}: #{value};"
    end)
    |> Enum.join("\n")
  end

  defp color_map_to_tailwind(color_map) do
    color_map
    |> Enum.into(%{}, fn {key, value} ->
      tailwind_key = key |> Atom.to_string() |> String.replace("_", "-")
      {tailwind_key, value}
    end)
  end

  defp spacing_map_to_tailwind(spacing_map) do
    spacing_map
    |> Enum.into(%{}, fn {key, value} ->
      {Atom.to_string(key), value}
    end)
  end

  defp shadow_map_to_tailwind(shadow_map) do
    shadow_map
    |> Enum.into(%{}, fn {key, value} ->
      {Atom.to_string(key), value}
    end)
  end

  defp animation_map_to_tailwind(animation_map) do
    animation_map
    |> Enum.into(%{}, fn {key, value} ->
      {Atom.to_string(key), value}
    end)
  end

  defp format_color_section(title, colors) do
    %{
      title: title,
      colors:
        Enum.map(colors, fn {key, hex} ->
          %{
            name: key |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize(),
            key: key,
            hex: hex,
            variants: get_color_variants(key)
          }
        end)
    }
  end

  defp get_color_variants(key) do
    case key do
      :primary -> ["#6eb3ff", "#0066ff", "#0044cc", "#002266"]
      :parse -> ["#33ffaa", "#00cc66"]
      :semantic -> ["#ff66ff", "#cc00cc"]
      :transform -> ["#66ffff", "#00cccc"]
      :error -> ["#ff3388"]
      :warning -> ["#ffcc33"]
      _ -> []
    end
  end
end
