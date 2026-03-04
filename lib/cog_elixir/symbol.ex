defmodule CogElixir.Symbol do
  @moduledoc false

  @scheme "file"
  @manager "."
  @version "unversioned"

  def module_symbol(package_name, module_name) do
    "#{@scheme} #{@manager} #{package_name} #{@version} #{escape_identifier(module_name)}#"
  end

  def function_symbol(package_name, module_name, func_name, arity) do
    "#{@scheme} #{@manager} #{package_name} #{@version} #{escape_identifier(module_name)}##{escape_identifier(Atom.to_string(func_name))}(#{arity})."
  end

  def macro_symbol(package_name, module_name, macro_name, arity) do
    function_symbol(package_name, module_name, macro_name, arity)
  end

  def field_symbol(package_name, module_name, field_name) do
    "#{@scheme} #{@manager} #{package_name} #{@version} #{escape_identifier(module_name)}##{escape_identifier(Atom.to_string(field_name))}."
  end

  def attribute_symbol(package_name, module_name, attr_name) do
    "#{@scheme} #{@manager} #{package_name} #{@version} #{escape_identifier(module_name)}##{escape_identifier(Atom.to_string(attr_name))}."
  end

  def type_symbol(package_name, module_name, type_name, arity) do
    "#{@scheme} #{@manager} #{package_name} #{@version} #{escape_identifier(module_name)}##{escape_identifier(Atom.to_string(type_name))}(#{arity})."
  end

  def callback_symbol(package_name, module_name, cb_name, arity) do
    function_symbol(package_name, module_name, cb_name, arity)
  end

  def local_symbol(index) do
    "local #{index}"
  end

  defp escape_identifier(name) do
    if simple_identifier?(name) do
      name
    else
      escaped = String.replace(name, "`", "``")
      "`#{escaped}`"
    end
  end

  defp simple_identifier?(name) do
    Regex.match?(~r/\A[a-zA-Z0-9_+\-$]+\z/, name)
  end
end
