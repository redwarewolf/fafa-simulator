class_name TreeStyle

## Column setup + row styling helpers for the Tree-based Hub lists.
## Every screen was repeating the same set_column_title / set_column_expand /
## set_column_custom_minimum_width triplet once per column.
##
## A spec is a Dictionary: {title, expand, min_width, ratio, align}.
## `align` sets the *cell* alignment applied later by align_row().
static func setup_columns(tree: Tree, specs: Array) -> void:
	tree.columns = specs.size()
	for i in specs.size():
		var spec : Dictionary = specs[i]
		tree.set_column_title(i, TranslationServer.translate(spec.get("title", "")))
		tree.set_column_expand(i, spec.get("expand", false))
		tree.set_column_custom_minimum_width(i, spec.get("min_width", 0))
		if spec.has("ratio"):
			tree.set_column_expand_ratio(i, spec["ratio"])

## Applies each spec's `align` to the matching cell of `item`.
static func align_row(item: TreeItem, specs: Array) -> void:
	for i in specs.size():
		var align : int = specs[i].get("align", HORIZONTAL_ALIGNMENT_LEFT)
		if align != HORIZONTAL_ALIGNMENT_LEFT:
			item.set_text_alignment(i, align)

## Paints every column of a row in the same colour.
static func tint_row(item: TreeItem, color: Color) -> void:
	var tree := item.get_tree()
	if tree == null:
		return
	for col in tree.columns:
		item.set_custom_color(col, color)
