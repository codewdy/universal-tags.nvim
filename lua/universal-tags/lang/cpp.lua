local M = {}

local LocalM = {}

local stop_node_type = {
  compound_statement = true,
  initializer_list = true,
}

function M.is_stop_node(node)
  return stop_node_type[node:type()] == true
end

declarator_processor_func = {}

function declarator_processor_func.bypass(node)
  return LocalM.declarator_process(node:child(1))
end

function declarator_processor_func.bypass_declarator(node)
    return LocalM.declarator_process(node:field('declarator')[1])
end

function declarator_processor_func.bypass_name(node)
    return LocalM.declarator_process(node:field('name')[1])
end

function declarator_processor_func.useit(node)
  return { node }
end

function declarator_processor_func.scope(node)
  local t1 = LocalM.declarator_process(node:field('scope')[1])
  local t2 = LocalM.declarator_process(node:field('name')[1])
  vim.list_extend(t1, t2)
  return t1
end

local declarator_processor = {
  namespace_identifier = declarator_processor_func.useit,
  type_identifier = declarator_processor_func.useit,
  identifier = declarator_processor_func.useit,
  field_identifier = declarator_processor_func.useit,
  destructor_name = declarator_processor_func.useit,
  pointer_declarator = declarator_processor_func.bypass,
  reference_declarator = declarator_processor_func.bypass,
  type_descriptor = declarator_processor_func.bypass_declarator,
  init_declarator = declarator_processor_func.bypass_declarator,
  field_declaration = declarator_processor_func.bypass_declarator,
  function_declarator = declarator_processor_func.bypass_declarator,
  template_type = declarator_processor_func.bypass_name,
  template_function = declarator_processor_func.bypass_name,
  qualified_identifier = declarator_processor_func.scope,
}

function LocalM.declarator_process(node)
  if node == nil then
    return { }
  end
  processor = declarator_processor[node:type()]
  if processor == nil then
    return { }
  end
  return processor(node)
end

symbol_processor_function = {}

function symbol_processor_function.declaration(node)
  local ret = {}
  for _,v in ipairs(node:field('declarator')) do
    local tags = LocalM.declarator_process(v)
    if #tags ~= 0 then
      table.insert(ret, {
        tags = tags,
        child_ids = {}
      })
    end
  end
  return ret
end

function symbol_processor_function.class_or_namespace(node)
  local ret = {}
  for _,v in ipairs(node:field('name')) do
    local tags = LocalM.declarator_process(v)
    if #tags ~= 0 then
      table.insert(ret, {
        tags = tags,
        child_ids = {}
      })
    end
  end
  if #ret ~= 0 then
    for _, child in ipairs(node:field('body')) do
      table.insert(ret[1].child_ids, child:id())
    end
  end
  return ret
end

function symbol_processor_function.alias(node)
  local ret = {}
  for _,v in ipairs(node:field('name')) do
    local tags = LocalM.declarator_process(v)
    if #tags ~= 0 then
      table.insert(ret, {
        tags = tags,
        child_ids = {}
      })
    end
  end
  return ret
end

function symbol_processor_function.using(node)
  local tags = LocalM.declarator_process(node:child(1))
  if #tags ~= 0 then
    return {{
      tags = {tags[#tags]},
      child_ids = {}
    }}
  else
    return {}
  end
end

local symbol_processor = {
  declaration = symbol_processor_function.declaration,
  field_declaration = symbol_processor_function.declaration,
  function_definition = symbol_processor_function.declaration,
  type_definition = symbol_processor_function.declaration,
  class_specifier = symbol_processor_function.class_or_namespace,
  struct_specifier = symbol_processor_function.class_or_namespace,
  namespace_definition = symbol_processor_function.class_or_namespace,
  alias_declaration = symbol_processor_function.alias,
  using_declaration = symbol_processor_function.using,
}

function M.get_symbols(node)
  local processor = symbol_processor[node:type()]
  if processor ~= nil then
    return processor(node)
  else
    return {}
  end
end

M.symbol_sep = '::'

return M
