const builtin = @import("builtin");
const std = @import("std");
const win = @import("win.zig");

const FILE_SIZE_BYTES_MAXIMUM = 5 * 1024;
const ELEMENTS_MAXIMUM_NUMBER = 128;
const ATTRIBUTES_MAXIMUM_NUMBER = 16;
const TEXT_LENGTH_MAXIMUM_BYTES = 8192;
const CSS_STYLE_RULES_MAXIMUM_NUMBER = 64;

const Tag = enum(u8) {
    dead,
    html,
    h1,
    body,
    div,
    p,
    em,
    b,
    a,
    title,
    span,
    button,
    text,
    br,
    hr,
};

const String = struct {
    start: u16 = 0,
    length: u16 = 0,
};

const Position = struct {
    x: u16 = 0,
    y: u16 = 0,
};

const Specificity = enum(u2) { id, class, tag };

const ParentStack = struct {
    arr: [ELEMENTS_MAXIMUM_NUMBER]*Node = undefined,
    array_size: u7 = 0,

    pub fn eof(self: *ParentStack) bool {
        if (self.array_size >= ELEMENTS_MAXIMUM_NUMBER - 1) {
            return true;
        }
        return false;
    }

    pub fn push(self: *ParentStack, node: *Node) void {
        self.arr[self.array_size] = node;
        if (!self.eof()) {
            self.array_size += 1;
        } else {
            unreachable;
        }
    }
    pub fn pop(self: *ParentStack) void {
        if (self.array_size > 0) {
            self.array_size -= 1;
        } else {
            unreachable;
        }
    }
    pub fn peek(self: *ParentStack) *Node {
        if (self.array_size > 0) {
            return self.arr[self.array_size - 1];
        } else {
            unreachable;
        }
    }
};

const AttributeKey = enum(u8) {
    text_color,
    background_color,
    position,
    width,
    height,
    margin,
    padding,
    font_size,
    font_weight,
    border_width,
    border_radius,
    display,
    font_family,
    text_decoration,
    align_items,
    null,
};

const Attribute = struct {
    key: AttributeKey,
    value: String,
    specificity: Specificity,
};

const AttributesList = struct {
    attributes: [ATTRIBUTES_MAXIMUM_NUMBER]Attribute = undefined,
    size_attributes: u8 = 0,

    fn add_attribute(self: *AttributesList, attribute: Attribute) void {
        if (self.size_attributes >= ATTRIBUTES_MAXIMUM_NUMBER) {
            return;
        }
        for (self.attributes[0..self.size_attributes]) |*item| {
            if ((item.key == attribute.key)) {
                // if the current specificity is higher or same (id is lowest), then update current item
                // else return
                if (@intFromEnum(item.specificity) >= @intFromEnum(attribute.specificity)) {
                    item.* = attribute;
                }
                return;
            }
        }

        self.attributes[self.size_attributes] = attribute;
        std.debug.print("Adding attribute: {s}\n", .{@tagName(attribute.key)});
        self.size_attributes += 1;
    }
};

const LayoutRect = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
};

const Node = struct {
    attributes: AttributesList = undefined,
    id: String = .{},
    class: String = .{},
    text: String = .{},
    tag: Tag = .dead,
    rect: LayoutRect = .{},

    id_parent: u8 = 0,
    id_node: u8 = 0,

    pub fn return_attributes(self: *Node, key: AttributeKey) ?Attribute {
        for (self.attributes.attributes) |attribute| {
            if (attribute.key == key) return attribute;
        }
        return null;
    }
};

const Dom = struct {
    nodes: [ELEMENTS_MAXIMUM_NUMBER]Node = undefined,
    nodes_size: u8 = 0,
};

var dom_nodes: Dom = .{};
var parent_struct: ParentStack = .{};
var html_parser: HTMlParser = .{};
var css_parser: CSSParser = .{};

const static_string_map_tag = std.StaticStringMap(Tag).initComptime(.{
    .{ "html", .html },
    .{ "h1", .h1 },
    .{ "body", .body },
    .{ "div", .div },
    .{ "p", .p },
    .{ "em", .em },
    .{ "b", .b },
    .{ "a", .a },
    .{ "title", .title },
    .{ "span", .span },
    .{ "button", .button },
    .{ "br", .br },
    .{ "hr", .hr },
});

const static_string_map_attribute_key = std.StaticStringMap(AttributeKey).initComptime(.{
    .{ "color", .text_color },
    .{ "background-color", .background_color },
    .{ "position", .position },
    .{ "width", .width },
    .{ "height", .height },
    .{ "margin", .margin },
    .{ "padding", .padding },
    .{ "border-width", .border_width },
    .{ "font-size", .font_size },
    .{ "font-weight", .font_weight },
    .{ "display", .display },
    .{ "border-radius", .border_radius },
    .{ "font-family", .font_family },
    .{ "text-decoration", .text_decoration },
    .{ "align-items", .align_items },
});

pub fn print_text_value(content: *[FILE_SIZE_BYTES_MAXIMUM]u8, string: String) void {
    const start = string.start;
    const end = start + string.length;
    std.debug.print("\n The string value is: {s}\n", .{content[start..end]});
}

const HTMlParser = struct {
    content: [FILE_SIZE_BYTES_MAXIMUM]u8 = undefined,

    length_content: u32 = 0,

    current_position: u16 = 0,

    node_number: u8 = 0,
    child_number: u8 = 0,

    pub fn eof(self: *HTMlParser) bool {
        return self.current_position >= self.length_content;
    }

    pub fn read_next_char(self: *HTMlParser) ?u8 {
        if (self.current_position + 1 >= self.length_content) {
            return null;
        }

        return self.content[self.current_position + 1];
    }

    pub fn starts_with_char(
        self: *HTMlParser,
        character: u8,
    ) bool {
        if (self.eof()) {
            return false;
        }

        return self.content[self.current_position] == character;
    }

    pub fn expect_character(
        self: *HTMlParser,
        character: u8,
    ) void {
        if (!self.starts_with_char(character)) {
            unreachable;
        }

        self.current_position += 1;
    }

    pub fn parse_name(self: *HTMlParser) String {
        const start = self.current_position;
        var length: u16 = 0;

        while (!self.eof()) {
            const character =
                self.content[self.current_position];

            if (!std.ascii.isAlphanumeric(character)) {
                break;
            }

            self.current_position += 1;
            length += 1;
        }

        return String{
            .start = start,
            .length = length,
        };
    }

    pub fn parse_text(self: *HTMlParser) String {
        while (true) {
            if (self.eof()) {
                break;
            }

            const character = self.content[self.current_position];
            if (std.ascii.isWhitespace(character) or std.ascii.isControl(character)) {
                self.current_position += 1;
            } else {
                break;
            }
        }

        const start = self.current_position;
        var length: u16 = 0;

        while (!self.eof()) {
            const character = self.content[self.current_position];

            // Text ends when we encounter '<' or "
            if (character == '<' or character == '"') {
                break;
            }

            self.current_position += 1;
            length += 1;
        }

        return String{
            .start = start,
            .length = length,
        };
    }

    pub fn print_current_character(self: *HTMlParser) void {
        std.debug.print("Current character:{c}\n", .{self.content[self.current_position]});
    }

    pub fn parse_id(self: *HTMlParser) void {
        // read id
        // read =
        // read ' or "
        // read the value
        // read ' or "
        const id = self.content[self.current_position..(self.current_position + 3)];
        std.debug.print("\nId value: {s} \n", .{id});
        if (!std.mem.eql(u8, "id=", id)) {
            return;
        }

        self.current_position += 3;
        self.print_current_character();
        self.expect_character('"');
        self.print_current_character();
        const id_value = self.parse_text();
        print_text_value(&self.content, id_value);
        dom_nodes.nodes[dom_nodes.nodes_size - 1].id = id_value;
        self.print_current_character();
        self.expect_character('"');
    }

    pub fn parse_class_name(self: *HTMlParser) void {
        // read class
        // read =
        // read ' or "
        // read the value
        // read ' or "
        const class = self.content[self.current_position..(self.current_position + 6)];
        std.debug.print("\nClass string: {s} \n", .{class});
        if (!std.mem.eql(u8, "class=", class)) {
            return;
        }

        self.current_position += 6;
        self.expect_character('"');
        self.print_current_character();
        const class_value = self.parse_text();
        print_text_value(&self.content, class_value);
        dom_nodes.nodes[dom_nodes.nodes_size - 1].class = class_value;
        self.expect_character('"');
    }

    pub fn parse_element(self: *HTMlParser) void {
        var node: Node = .{};

        self.expect_character('<');
        if (self.starts_with_char('/')) {
            while (true) {
                if (self.starts_with_char('>')) {
                    self.current_position += 1;
                    break;
                }
                self.current_position += 1;
            }

            parent_struct.pop();

            return;
        }

        const tag_name_string = self.parse_name();
        const tag_name = self.content[tag_name_string.start..(tag_name_string.start + tag_name_string.length)];

        node.tag = static_string_map_tag.get(tag_name) orelse .dead;

        if (node.tag != .dead) {
            node.id_node = self.node_number;

            if (parent_struct.array_size > 0) {
                node.id_parent = parent_struct.peek().*.id_node;
            } else {
                node.id_parent = 0;
            }
            self.node_number += 1;

            dom_nodes.nodes[dom_nodes.nodes_size] = node;
            parent_struct.push(&dom_nodes.nodes[dom_nodes.nodes_size]);
            dom_nodes.nodes_size += 1;
        }

        // For now, skip everything until '>'.
        while (!self.eof()) {
            if (self.starts_with_char('i')) {
                self.parse_id();
            }

            if (self.starts_with_char('c')) {
                self.parse_class_name();
            }

            if (self.starts_with_char('>')) {
                break;
            }

            self.current_position += 1;
        }

        // Consume '>'.
        if (!self.eof()) {
            self.expect_character('>');
        }

        if (dom_nodes.nodes_size >= ELEMENTS_MAXIMUM_NUMBER) {
            unreachable;
        }

        // handle cases for br and hr they don't have a closing tag
        if (node.tag == .br or node.tag == .hr) {
            parent_struct.pop();
        }
    }

    pub fn parse_node(self: *HTMlParser) void {
        if (self.starts_with_char('<')) {
            self.parse_element();
        } else {
            const text = self.parse_text();

            // For now, create a text node.
            if (text.length > 0) {
                if (dom_nodes.nodes_size >= ELEMENTS_MAXIMUM_NUMBER) {
                    unreachable;
                }

                var node: Node = .{};
                node.tag = .text;
                node.text = text;
                node.id_parent = parent_struct.peek().*.id_node;
                node.id_node = self.node_number;

                dom_nodes.nodes[dom_nodes.nodes_size] = node;
                dom_nodes.nodes_size += 1;
            }
        }
    }

    pub fn parse(self: *HTMlParser) void {
        while (!self.eof()) {
            self.parse_node();
        }
    }
};

const CSSSelector = struct {
    selector: String,
    specificity: Specificity = .tag,
};

// assume unit is px
// colors will be in hex
const CSSParser = struct {
    // make a attributes struct for each element
    // and the copy it to every node that has that element
    content: [FILE_SIZE_BYTES_MAXIMUM]u8 = undefined,
    //attributes: [ELEMENTS_MAXIMUM_NUMBER]AttributesList = undefined,

    length_content: u32 = 0,

    current_position: u16 = 0,

    pub fn print_current_character(self: *CSSParser) void {
        std.debug.print("Current character:{d}\n", .{self.content[self.current_position]});
    }

    fn eof(self: *CSSParser) bool {
        return self.current_position >= self.length_content;
    }

    fn consume_whitespace(self: *CSSParser) void {
        while (!self.eof()) {
            if (self.content[self.current_position] != ' ') {
                self.current_position += 1;
            } else {
                break;
            }
        }
    }

    pub fn expect_character(
        self: *CSSParser,
        character: u8,
    ) void {
        if (!self.starts_with_char(character)) {
            //std.debug.print("Character: {c}", .{character});
            unreachable;
        }

        self.current_position += 1;
    }

    pub fn parse_selector(self: *CSSParser) CSSSelector {
        var start = self.current_position;
        var length: u16 = 0;

        var selector: CSSSelector = undefined;

        const character_first: u8 =
            self.content[self.current_position];
        switch (character_first) {
            // class
            '.' => {
                selector.specificity = .class;
                self.current_position += 1;
                start = start + 1;
            },
            // id
            '#' => {
                selector.specificity = .id;
                self.current_position += 1;
                start = start + 1;
            },
            // tag
            else => {
                selector.specificity = .tag;
            },
        }
        while (true) {
            const character = self.content[self.current_position];
            if (!std.ascii.isAlphanumeric(character)) {
                break;
            }
            self.current_position += 1;
            length += 1;
        }
        selector.selector.start = start;
        selector.selector.length = length;

        return selector;
    }

    pub fn starts_with_char(
        self: *CSSParser,
        character: u8,
    ) bool {
        if (self.eof()) {
            return false;
        }

        return self.content[self.current_position] == character;
    }

    pub fn parse_attribute_key(self: *CSSParser) String {
        const start = self.current_position;
        var length: u16 = 0;

        while (!self.eof()) {
            const character =
                self.content[self.current_position];

            // background-color
            if (character == ':') {
                break;
            }

            self.current_position += 1;
            length += 1;
        }

        return String{
            .start = start,
            .length = length,
        };
    }

    pub fn parse_attribute_value(self: *CSSParser) String {
        const start = self.current_position;
        var length: u16 = 0;

        while (!self.eof()) {
            const character =
                self.content[self.current_position];

            if (character == ';') {
                break;
            }

            self.current_position += 1;
            length += 1;
        }

        return String{
            .start = start,
            .length = length,
        };
    }

    fn parse(self: *CSSParser) void {
        // 5 attributes
        //var attributes: Attributes = .{};
        // parse selector
        // parse declaration

        while (!self.eof()) {
            // parse tag
            const selector: CSSSelector = self.parse_selector();
            self.expect_character('{');
            while (!self.starts_with_char('}')) {
                const key_string: String = self.parse_attribute_key();
                const key_name = self.content[key_string.start..(key_string.start + key_string.length)];

                const key: AttributeKey = static_string_map_attribute_key.get(key_name) orelse .null;
                self.expect_character(':');
                const value = self.parse_attribute_value();
                self.expect_character(';');

                const selector_start = selector.selector.start;
                const selector_end = selector.selector.start + selector.selector.length;

                const value_start = value.start;
                const value_end = value.start + value.length;

                const attribute: Attribute = .{
                    .key = key,
                    .value = value,
                    .specificity = selector.specificity,
                };

                switch (attribute.specificity) {
                    .tag => {
                        // find all the nodes with that tag
                        //
                        var index: u8 = 0;
                        while (index < dom_nodes.nodes_size) : (index += 1) {
                            if (dom_nodes.nodes[index].tag == static_string_map_tag.get(self.content[selector_start..selector_end])) {
                                dom_nodes.nodes[index].attributes.add_attribute(attribute);
                            }
                        }
                    },
                    .class => {
                        var index: u8 = 0;
                        while (index < dom_nodes.nodes_size) : (index += 1) {
                            const start = dom_nodes.nodes[index].class.start;
                            const end = start + dom_nodes.nodes[index].class.length;
                            const className = html_parser.content[start..end];

                            std.debug.print("ClassName: {s}", .{className});
                            print_text_value(&self.content, selector.selector);

                            if (std.mem.eql(u8, className, self.content[selector_start..selector_end])) {
                                dom_nodes.nodes[index].attributes.add_attribute(attribute);
                            }
                        }
                    },
                    .id => {
                        var index: u8 = 0;
                        while (index < dom_nodes.nodes_size) : (index += 1) {
                            const start = dom_nodes.nodes[index].id.start;
                            const end = start + dom_nodes.nodes[index].id.length;
                            const id = html_parser.content[start..end];

                            if (std.mem.eql(u8, id, self.content[selector_start..selector_end])) {
                                dom_nodes.nodes[index].attributes.add_attribute(attribute);
                            }
                        }
                    },
                }

                std.debug.print("Selector: {s} | Attribute: {s} | Value:{s} | Specificity:{s}\n", .{
                    self.content[selector_start..selector_end],
                    @tagName(key),
                    self.content[value_start..value_end],
                    @tagName(selector.specificity),
                });
            }
            self.expect_character('}');
        }
    }
};

pub fn calculate_width(index: usize) void {
    // 0 would be the html tag
    if (index > 0) {
        var total: i32 = 0;
        for (dom_nodes.nodes[index].attributes.attributes) |item| {
            switch (item.key) {
                .border_width, .margin, .padding => {
                    // assuming every value for the above attributes has a px attached
                    if (item.value.start <= 0) continue;
                    const start = item.value.start;
                    const end = start + item.value.length - 2;
                    const value = std.fmt.parseInt(i32, css_parser.content[start..end], 10) catch 0;
                    // multiply by 2 for either side
                    total += value * 2;
                },
                .width => {
                    // assuming every value for the above attributes has a px attached
                    if (item.value.start <= 0) continue;
                    const start = item.value.start;
                    const end = start + item.value.length - 2;
                    const value = std.fmt.parseInt(i32, css_parser.content[start..end], 10) catch 0;
                    // don't multiply
                    total += value;
                },
                else => {},
            }
        }

        dom_nodes.nodes[index].rect.width = dom_nodes.nodes[dom_nodes.nodes[index].id_parent].rect.width - total;
    } else {
        dom_nodes.nodes[index].rect.width = win.WIDTH_MAX;
    }
}

pub fn return_css_int_value(index: u8, key: AttributeKey) i32 {
    const attribute = dom_nodes.nodes[index].return_attributes(key) orelse return 0;
    const attribute_value: i32 = std.fmt.parseInt(
        i32,
        // -2 to remove the "px"
        css_parser.content[attribute.value.start..(attribute.value.start + attribute.value.length - 2)],
        10,
    ) catch 0;

    return attribute_value;
}

pub fn calculate_position_x(index: u8) void {
    // here x, y are boxes not included in the padding
    const margin = return_css_int_value(index, AttributeKey.margin);
    const padding = return_css_int_value(index, AttributeKey.padding);
    const border_width = return_css_int_value(index, AttributeKey.border_width);

    if (index > 0) {
        // take parents x,y as well
        const parent_position_x = dom_nodes.nodes[dom_nodes.nodes[index].id_parent].rect.x;
        dom_nodes.nodes[index].rect.x = border_width + margin + padding + parent_position_x;
    } else {
        // for html node there is no parent container
        dom_nodes.nodes[index].rect.x = border_width + margin + padding;
    }
}

pub fn calculate_layout() void {
    // calculate width of everything
    // full size - (the margins + border_width + parent padding)
    //

    var i: u8 = 0;
    while (i < dom_nodes.nodes_size) : (i += 1) {
        calculate_width(i);
        calculate_position_x(i);
    }
}

pub fn debug_print() void {
    var i: usize = 0;

    while (i < dom_nodes.nodes_size) : (i += 1) {
        const node = dom_nodes.nodes[i];

        std.debug.print("\n================ Node {d} ================\n", .{i});

        // Basic node information
        std.debug.print("tag:       {s}\n", .{@tagName(node.tag)});
        std.debug.print("id_node:   {d}\n", .{node.id_node});
        std.debug.print("id_parent: {d}\n", .{node.id_parent});

        // ID
        const id_start = node.id.start;
        const id_end = id_start + node.id.length;
        std.debug.print("id:        \"{s}\"\n", .{
            html_parser.content[id_start..id_end],
        });

        // Class
        const class_start = node.class.start;
        const class_end = class_start + node.class.length;
        std.debug.print("class:     \"{s}\"\n", .{
            html_parser.content[class_start..class_end],
        });

        // Text
        const text_start = node.text.start;
        const text_end = text_start + node.text.length;
        std.debug.print("text:      \"{s}\"\n", .{
            html_parser.content[text_start..text_end],
        });

        // Layout rectangle
        std.debug.print(
            "rect:      x={d}, y={d}, width={d}, height={d}\n",
            .{
                node.rect.x,
                node.rect.y,
                node.rect.width,
                node.rect.height,
            },
        );

        // Attributes
        std.debug.print("attributes ({d}):\n", .{
            node.attributes.size_attributes,
        });

        var j: usize = 0;
        while (j < node.attributes.size_attributes) : (j += 1) {
            const attribute = node.attributes.attributes[j];

            const value_start = attribute.value.start;
            const value_end = value_start + attribute.value.length;

            std.debug.print(
                "  {s}: \"{s}\" ({s})\n",
                .{
                    @tagName(attribute.key),
                    css_parser.content[value_start..value_end],
                    @tagName(attribute.specificity),
                },
            );
        }
    }
}

pub fn main() anyerror!void {
    html_parser.length_content = win.read_file(&html_parser.content, true);

    // remove carriage return or line feed
    if (html_parser.length_content >= 2 and
        html_parser.content[html_parser.length_content - 2] == '\r' and
        html_parser.content[html_parser.length_content - 1] == '\n')
    {
        html_parser.length_content -= 2;
    }

    css_parser.length_content = win.read_file(&css_parser.content, false);

    // remove  carriage return or line feed
    if (css_parser.length_content >= 2 and
        css_parser.content[css_parser.length_content - 2] == '\r' and
        css_parser.content[css_parser.length_content - 1] == '\n')
    {
        css_parser.length_content -= 2;
    }

    html_parser.parse();
    css_parser.parse();

    calculate_layout();

    // Only do the debug print stuff if in debug mode
    if (builtin.mode == .Debug) {
        debug_print();
    }

    win.Create();
}
