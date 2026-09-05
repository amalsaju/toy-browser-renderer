const builtin = @import("builtin");
const std = @import("std");
const win = @import("win.zig");
const rand = std.crypto;

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

const Dimensions = struct {
    content: LayoutRect = .{},
    padding: EdgeSizes = .{},
    border: EdgeSizes = .{},
    margin: EdgeSizes = .{},
};

const EdgeSizes = struct {
    left: i32 = 0,
    right: i32 = 0,
    top: i32 = 0,
    bottom: i32 = 0,
};

const CssValue = union(enum) {
    edge_value: EdgeSizes,
    string_value: String,
    color_value: win.rgb_value,
    integer_value: i32,
};

const Attribute = struct {
    key: AttributeKey = .null,
    value: CssValue,
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
        //std.debug.print("Adding attribute: {s}\n", .{@tagName(attribute.key)});
        self.size_attributes += 1;
    }

    fn return_attribute(self: *AttributesList, key: AttributeKey) ?*Attribute {
        for (self.attributes[0..]) |*attribute| {
            if (attribute.key == key) {
                return attribute;
            }
        }
        return null;
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
    dimensions: Dimensions = undefined,

    id_parent: u8 = 0,
    id_node: u8 = 0,
};

const Dom = struct {
    nodes: [ELEMENTS_MAXIMUM_NUMBER]Node = undefined,
    nodes_size: u8 = 0,

    pub fn return_parent_index(self: *Dom, index: usize) u8 {
        for (self.nodes, 0..) |node, i| {
            if (self.nodes[index].id_parent == node.id_node) {
                if (node.tag != .text) {
                    return @as(u8, @intCast(i));
                }
            }
        }
        return 0;
    }
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

// pub fn print_text_value(content: *[FILE_SIZE_BYTES_MAXIMUM]u8, string: String) void {
//     const start = string.start;
//     const end = start + string.length;
//     std.debug.print("\n The string value is: {s}\n", .{content[start..end]});
// }

const HTMlParser = struct {
    content: [FILE_SIZE_BYTES_MAXIMUM]u8 = undefined,

    length_content: u32 = 0,

    current_position: u16 = 0,

    node_number: u8 = 0,

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

    // pub fn print_current_character(self: *HTMlParser) void {
    //     std.debug.print("Current character:{c}\n", .{self.content[self.current_position]});
    // }

    pub fn parse_id(self: *HTMlParser) void {
        // read id
        // read =
        // read ' or "
        // read the value
        // read ' or "
        const id = self.content[self.current_position..(self.current_position + 3)];
        //std.debug.print("\nId value: {s} \n", .{id});
        if (!std.mem.eql(u8, "id=", id)) {
            return;
        }

        self.current_position += 3;
        //self.print_current_character();
        self.expect_character('"');
        //self.print_current_character();
        const id_value = self.parse_text();
        //print_text_value(&self.content, id_value);
        dom_nodes.nodes[dom_nodes.nodes_size - 1].id = id_value;
        //self.print_current_character();
        self.expect_character('"');
    }

    pub fn parse_class_name(self: *HTMlParser) void {
        // read class
        // read =
        // read ' or "
        // read the value
        // read ' or "
        const class = self.content[self.current_position..(self.current_position + 6)];
        //std.debug.print("\nClass string: {s} \n", .{class});
        if (!std.mem.eql(u8, "class=", class)) {
            return;
        }

        self.current_position += 6;
        self.expect_character('"');
        //self.print_current_character();
        const class_value = self.parse_text();
        //print_text_value(&self.content, class_value);
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

    // pub fn print_current_character(self: *CSSParser) void {
    //     std.debug.print("Current character:{d}\n", .{self.content[self.current_position]});
    // }

    fn eof(self: *CSSParser) bool {
        return self.current_position >= self.length_content;
    }

    fn consume_space_and_controls(self: *CSSParser) void {
        while (!self.eof()) {
            const character = self.content[self.current_position];
            if (character == ' ' or (character == '\r' or (character == '\n'))) {
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
            self.consume_space_and_controls();
            const selector: CSSSelector = self.parse_selector();
            self.consume_space_and_controls();
            self.expect_character('{');
            while (!self.starts_with_char('}')) {
                self.consume_space_and_controls();
                const key_string: String = self.parse_attribute_key();

                self.consume_space_and_controls();
                const key_name = self.content[key_string.start..(key_string.start + key_string.length)];

                const key: AttributeKey = static_string_map_attribute_key.get(key_name) orelse .null;
                self.expect_character(':');

                self.consume_space_and_controls();
                const value_string = self.parse_attribute_value();

                self.consume_space_and_controls();
                self.expect_character(';');

                const selector_start = selector.selector.start;
                const selector_end = selector.selector.start + selector.selector.length;

                const value_start = value_string.start;
                const value_end = value_string.start + value_string.length;

                var value: CssValue = undefined;
                switch (key) {
                    .margin, .border_width, .padding => {
                        const integer_value: i32 = std.fmt.parseInt(
                            i32,
                            // -2 to remove the "px"
                            css_parser.content[value_start..(value_end - 2)],
                            10,
                        ) catch 0;

                        // value is edgevalue with 4 side values
                        value = .{
                            .edge_value = EdgeSizes{
                                .left = integer_value,
                                .bottom = integer_value,
                                .right = integer_value,
                                .top = integer_value,
                            },
                        };
                    },
                    .text_color, .background_color => {
                        // value is a rgb struct
                        // start from 1 because 0 is #
                        const color = std.fmt.parseInt(u32, css_parser.content[(value_start + 1)..(value_start + 7)], 16) catch 0;
                        const r: u8 = @truncate((color >> 16) & 0xFF);
                        const g: u8 = @truncate((color >> 8) & 0xFF);
                        const b: u8 = @truncate(color & 0xFF);
                        std.debug.print("Color value: {s}", .{css_parser.content[(value_start + 1)..(value_start + 7)]});
                        std.debug.print("Color from css : r:{d}, g:{d}, b:{d} ", .{ r, g, b });
                        value = .{
                            .color_value = win.rgb_value{ .r = r, .g = g, .b = b },
                        };
                    },
                    .width, .height => {
                        const integer_value: i32 = std.fmt.parseInt(
                            i32,
                            // -2 to remove the "px"
                            css_parser.content[value_start..(value_end - 2)],
                            10,
                        ) catch 0;
                        value = .{ .integer_value = integer_value };
                    },
                    else => {
                        // all strings here for now
                        value = .{ .string_value = value_string };
                    },
                }

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

                            //std.debug.print("ClassName: {s}", .{className});
                            //print_text_value(&self.content, selector.selector);

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

                // std.debug.print("Selector: {s} | Attribute: {s} | Value:{s} | Specificity:{s}\n", .{
                //     self.content[selector_start..selector_end],
                //     @tagName(key),
                //     self.content[value_start..value_end],
                //     @tagName(selector.specificity),
                // });
                self.consume_space_and_controls();
            }
            self.expect_character('}');
        }
    }
};

pub fn calculate_width(index: usize) void {
    if (index == 0) {
        dom_nodes.nodes[0].dimensions.content.x = 0;
        dom_nodes.nodes[0].dimensions.content.y = 0;
        dom_nodes.nodes[0].dimensions.content.width = win.width_current;
        return;
    }

    if (dom_nodes.nodes[index].tag == .text) {
        // maybe text doesn't need any of this ?
        // TODO: will need to change this as text
        const parent = dom_nodes.nodes[dom_nodes.return_parent_index(index)];
        dom_nodes.nodes[index].dimensions.content.x = parent.dimensions.content.x;
        dom_nodes.nodes[index].dimensions.content.y = parent.dimensions.content.y;
        dom_nodes.nodes[index].dimensions.content.width = parent.dimensions.content.width;
        return;
    }
    // for certain tag, if there is no width specified, get the width of the text in it

    // total will be the min space required by the element
    var margin_left = if (dom_nodes.nodes[index].attributes.return_attribute(.margin)) |attribute| attribute.value.edge_value.left else 0;
    var margin_right = if (dom_nodes.nodes[index].attributes.return_attribute(.margin)) |attribute| attribute.value.edge_value.right else 0;
    const padding_left = if (dom_nodes.nodes[index].attributes.return_attribute(.padding)) |attribute| attribute.value.edge_value.left else 0;
    const padding_right = if (dom_nodes.nodes[index].attributes.return_attribute(.padding)) |attribute| attribute.value.edge_value.right else 0;
    const border_width_left = if (dom_nodes.nodes[index].attributes.return_attribute(.border_width)) |attribute| attribute.value.edge_value.left else 0;
    const border_width_right = if (dom_nodes.nodes[index].attributes.return_attribute(.border_width)) |attribute| attribute.value.edge_value.right else 0;

    var width = if (dom_nodes.nodes[index].attributes.return_attribute(.width)) |attribute| attribute.value.integer_value else 0;

    const total = padding_left + padding_right + border_width_left + border_width_right + width;

    const underflow = dom_nodes.nodes[dom_nodes.return_parent_index(index)].dimensions.content.width - total;

    // we are gonna assume 0 value means auto which means it can expand or contract
    // need to match 5 cases
    // width == auto, margin_left == auto, margin_right == auto (auto will be 0 for our case)
    // false, false, false
    // false, false, true
    // false, true, false
    // true , _, _ => if width is auto, any other auto values become 0
    // false, true, true

    if (width > 0 and margin_left > 0 and margin_right > 0) {
        margin_right += underflow;
    } else if (width > 0 and margin_left > 0 and margin_right == 0) {
        margin_right = underflow;
    } else if (width > 0 and margin_left == 0 and margin_right > 0) {
        margin_left = underflow;
    } else if (width == 0) {
        if (underflow >= 0) {
            width = underflow;
        } else {
            width = 0;
            margin_right += underflow;
        }
    } else if (width > 0 and margin_left == 0 and margin_right == 0) {
        margin_left = @divFloor(underflow, 2);
        margin_right = @divFloor(underflow, 2);
    }

    // create a dimensions struct on the node and update these values in that
    // don't update the actual html and css values back
    dom_nodes.nodes[index].dimensions.margin.left = margin_left;
    dom_nodes.nodes[index].dimensions.margin.right = margin_right;
    dom_nodes.nodes[index].dimensions.padding.left = padding_left;
    dom_nodes.nodes[index].dimensions.padding.right = padding_right;
    dom_nodes.nodes[index].dimensions.border.left = border_width_left;
    dom_nodes.nodes[index].dimensions.border.right = border_width_right;

    dom_nodes.nodes[index].dimensions.content.width = width;
}

pub fn calculate_position_x(index: u8) void {
    const parent_dimensions = dom_nodes.nodes[dom_nodes.return_parent_index(index)].dimensions;

    const margin_left = dom_nodes.nodes[index].dimensions.margin.left;

    dom_nodes.nodes[index].dimensions.content.x = parent_dimensions.content.x + parent_dimensions.padding.left + parent_dimensions.border.left + margin_left;
}

pub fn return_html_height() i32 {
    return dom_nodes.nodes[0].dimensions.content.height;
}

pub fn calculate_height(index: u8) void {
    if (dom_nodes.nodes[index].tag == .text) {
        // const parent_id_returned = dom_nodes.return_parent_index(index);
        // const parent_node = dom_nodes.nodes[dom_nodes.return_parent_index(index)];
        dom_nodes.nodes[dom_nodes.return_parent_index(index)].dimensions.content.height += 20;

        // calculate the text height and add it to its parents
    } else if (dom_nodes.nodes[index].tag == .br) {
        dom_nodes.nodes[index].dimensions.content.height = 20;
    } else if (dom_nodes.nodes[index].tag == .html) {
        const current_height = dom_nodes.nodes[0].dimensions.content.height;
        dom_nodes.nodes[0].dimensions.content.height = if (current_height < win.RENDER_HEIGHT_MAX) win.RENDER_HEIGHT_MAX else current_height;
    } else if (dom_nodes.nodes[index].tag == .body) {
        // use the html height attribute rather than the dimension if the height is available
        // else use the html height dimension
        const margin_top = if (dom_nodes.nodes[index].attributes.return_attribute(.margin)) |attribute| attribute.value.edge_value.top else 0;
        const margin_bottom = if (dom_nodes.nodes[index].attributes.return_attribute(.margin)) |attribute| attribute.value.edge_value.bottom else 0;

        const padding_top = if (dom_nodes.nodes[index].attributes.return_attribute(.padding)) |attribute| attribute.value.edge_value.top else 0;
        const padding_bottom = if (dom_nodes.nodes[index].attributes.return_attribute(.padding)) |attribute| attribute.value.edge_value.bottom else 0;

        const border_width_top = if (dom_nodes.nodes[index].attributes.return_attribute(.border_width)) |attribute| attribute.value.edge_value.top else 0;
        const border_width_bottom = if (dom_nodes.nodes[index].attributes.return_attribute(.border_width)) |attribute| attribute.value.edge_value.bottom else 0;

        var height: i32 = 0;

        // if body has a height attribute => use that
        if (dom_nodes.nodes[index].attributes.return_attribute(.height)) |attribute| {
            height = attribute.value.integer_value;
        }
        // else if html has a height attribute use that
        else if (dom_nodes.nodes[0].attributes.return_attribute(.height)) |attribute| {
            height = attribute.value.integer_value;
        }

        dom_nodes.nodes[index].dimensions.content.height += padding_top + padding_bottom + border_width_top + border_width_bottom + height;
        dom_nodes.nodes[index].dimensions.margin.top = margin_top;
        dom_nodes.nodes[index].dimensions.margin.bottom = margin_bottom;
        dom_nodes.nodes[index].dimensions.padding.top = padding_top;
        dom_nodes.nodes[index].dimensions.padding.bottom = padding_bottom;
        dom_nodes.nodes[index].dimensions.border.top = border_width_top;
        dom_nodes.nodes[index].dimensions.border.bottom = border_width_bottom;

        dom_nodes.nodes[index].dimensions.content.height = height;
        // add to the height of the html if overflowing
        const overflow: i32 = margin_top + margin_bottom + dom_nodes.nodes[index].dimensions.content.height - dom_nodes.nodes[0].dimensions.content.height;
        if (overflow > 0) {
            dom_nodes.nodes[0].dimensions.content.height += overflow;
        }
    } else {
        const margin_top = if (dom_nodes.nodes[index].attributes.return_attribute(.margin)) |attribute| attribute.value.edge_value.top else 0;
        const margin_bottom = if (dom_nodes.nodes[index].attributes.return_attribute(.margin)) |attribute| attribute.value.edge_value.bottom else 0;

        const padding_top = if (dom_nodes.nodes[index].attributes.return_attribute(.padding)) |attribute| attribute.value.edge_value.top else 0;
        const padding_bottom = if (dom_nodes.nodes[index].attributes.return_attribute(.padding)) |attribute| attribute.value.edge_value.bottom else 0;

        const border_width_top = if (dom_nodes.nodes[index].attributes.return_attribute(.border_width)) |attribute| attribute.value.edge_value.top else 0;
        const border_width_bottom = if (dom_nodes.nodes[index].attributes.return_attribute(.border_width)) |attribute| attribute.value.edge_value.bottom else 0;

        const height = if (dom_nodes.nodes[index].attributes.return_attribute(.height)) |attribute| attribute.value.integer_value else dom_nodes.nodes[index].dimensions.content.height;

        dom_nodes.nodes[index].dimensions.content.height += padding_top + padding_bottom + border_width_top + border_width_bottom + height;
        dom_nodes.nodes[index].dimensions.margin.top = margin_top;
        dom_nodes.nodes[index].dimensions.margin.bottom = margin_bottom;
        dom_nodes.nodes[index].dimensions.padding.top = padding_top;
        dom_nodes.nodes[index].dimensions.padding.bottom = padding_bottom;
        dom_nodes.nodes[index].dimensions.border.top = border_width_top;
        dom_nodes.nodes[index].dimensions.border.bottom = border_width_bottom;

        dom_nodes.nodes[index].dimensions.content.height = height;
        //std.debug.print("\n Height of node at {d}: {d}", .{ index, dom_nodes.nodes[index].dimensions.content.height });

        // html parent index is also 0 so we have to except that
        if (dom_nodes.nodes[index].tag == .html) return;
        dom_nodes.nodes[dom_nodes.return_parent_index(index)].dimensions.content.height += margin_top + margin_bottom + dom_nodes.nodes[index].dimensions.content.height;
        // std.debug.print("\n Height of node parent at {d}: {d}", .{
        //     dom_nodes.return_parent_index(index),
        //     dom_nodes.nodes[dom_nodes.return_parent_index(index)].dimensions.content.height,
        // });
    }
}

pub fn calculate_position_y(index: u8) void {
    const parent_dimensions = dom_nodes.nodes[dom_nodes.return_parent_index(index)].dimensions;

    const margin_top = dom_nodes.nodes[index].dimensions.margin.top;
    var previous_children_height: i32 = 0;
    var i: u8 = dom_nodes.return_parent_index(index) + 1;
    while (i < index) : (i += 1) {
        if (dom_nodes.nodes[i].id_parent == dom_nodes.nodes[index].id_parent) {
            previous_children_height += dom_nodes.nodes[i].dimensions.content.height + dom_nodes.nodes[i].dimensions.margin.top + dom_nodes.nodes[i].dimensions.margin.bottom;
        }
    }

    dom_nodes.nodes[index].dimensions.content.y = parent_dimensions.content.y + parent_dimensions.padding.top + parent_dimensions.border.top + margin_top + previous_children_height;
}

pub fn calculate_layout() void {
    // calculate width of everything
    // full size - (the margins + border_width + parent padding)

    for (&dom_nodes.nodes) |*node| {
        node.*.dimensions.content.x = 0;
        node.*.dimensions.content.y = 0;
        node.*.dimensions.content.width = 0;
        node.*.dimensions.content.height = 0;
    }

    var i: u8 = 0;
    while (i < dom_nodes.nodes_size) : (i += 1) {
        calculate_width(i);
        calculate_position_x(i);
    }
    i = dom_nodes.nodes.len - 1;
    // since i is u8 it can't go to -1
    // calculate height of the html tag
    // because for rendering reasons, it fills the whole area
    // even though the bounding box is smaller
    // so for our purposes the height is the whole area
    // irrespective of whether a height value is provided
    // but that value will affect the body height
    calculate_height(0);

    while (i > 0) : (i -= 1) {
        calculate_height(i);
    }
    // now you can calcualte the height in order
    while (i < dom_nodes.nodes_size) : (i += 1) {
        calculate_position_y(i);
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
            "Content Size:      x={d}, y={d}, width={d}, height={d}\n",
            .{
                node.dimensions.content.x,
                node.dimensions.content.y,
                node.dimensions.content.width,
                node.dimensions.content.height,
            },
        );

        // Attributes
        std.debug.print("attributes ({d}):\n", .{
            node.attributes.size_attributes,
        });

        for (node.attributes.attributes, 0..) |attribute, j| {
            if (j >= node.attributes.size_attributes) break;
            std.debug.print("{d}: {s} = ", .{
                j + 1,
                @tagName(attribute.key),
            });

            switch (attribute.value) {
                .edge_value => |edge| {
                    std.debug.print(
                        "{{ left={d}, right={d}, top={d}, bottom={d} }}",
                        .{
                            edge.left,
                            edge.right,
                            edge.top,
                            edge.bottom,
                        },
                    );
                },

                .string_value => |string| {
                    std.debug.print(
                        "\"{s}\"",
                        .{
                            css_parser.content[string.start..(string.start + string.length)],
                        },
                    );
                },

                .color_value => |color| {
                    std.debug.print(
                        "#{X:0>2}{X:0>2}{X:0>2}",
                        .{
                            color.r,
                            color.g,
                            color.b,
                        },
                    );
                },

                .integer_value => |value| {
                    std.debug.print("{d}", .{value});
                },
            }

            std.debug.print(" ({s})\n", .{
                @tagName(attribute.specificity),
            });
        }
    }
}

pub const rgb_value = struct {
    a: u8 = 0,
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
};

const Random = struct {
    state: u32,

    pub fn init(seed: u32) Random {
        return .{
            .state = seed,
        };
    }

    pub fn next(self: *Random) u32 {
        var x = self.state;

        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;

        self.state = x;
        return x;
    }

    pub fn rgb(self: *Random) win.rgb_value {
        return .{
            .a = 0,
            .r = @truncate(self.next()),
            .g = @truncate(self.next()),
            .b = @truncate(self.next()),
        };
    }
};

pub fn render_layout() void {
    // clear bit map memory
    win.render_box(0, 0, win.width_current, win.height_current, win.rgb_value{ .r = 255, .g = 255, .b = 255 });
    for (&dom_nodes.nodes) |*node| {
        if (node.tag == .text) continue;

        var rgb: win.rgb_value = .{ .r = 0, .g = 0, .b = 0 };
        if (node.attributes.return_attribute(.background_color) != null) {
            const color_value = node.attributes.return_attribute(.background_color).?.value.color_value;
            rgb.r = color_value.r;
            rgb.g = color_value.g;
            rgb.b = color_value.b;
            win.render_box(node.dimensions.content.x, node.dimensions.content.y, node.dimensions.content.width, node.dimensions.content.height, rgb);
        }
        if (rgb.r > 0 or rgb.g > 0 or rgb.b > 0) {
            std.debug.print("RGB Value: {d} {d} {d}\n", .{ rgb.r, rgb.g, rgb.b });
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

    //calculate_layout();
    //render_layout();

    win.Create();
    // Only do the debug print stuff if in debug mode
    if (builtin.mode == .Debug) {
        debug_print();
    }
}
