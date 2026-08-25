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

const AttributeKey = enum(u8) {
    text_color,
    background_color,
    position,
    width,
    height,
    margin,
    padding,
};
const AttributeValue = union(enum) {
    text_color: u32,
    background_color: u32,
    position: Position,
    width: u16,
    height: u16,
    margin: u16,
    padding: u16,
};

const Attribute = struct {
    key: AttributeKey,
    value: AttributeValue,
    specificity: Specificity,
};

const Attributes = struct {
    attributes: [ATTRIBUTES_MAXIMUM_NUMBER]Attribute,
    size_attributes: u8,
};

const Node = struct {
    attributes: Attributes = undefined,
    id: String = .{},
    class: String = .{},
    text: String = .{},
    tag: Tag = .dead,

    id_parent: u8 = 0,
    id_node: u8 = 0,
};

const Dom = struct {
    nodes: [ELEMENTS_MAXIMUM_NUMBER]Node = undefined,
    nodes_size: u8 = 0,
};

var dom_nodes: Dom = .{};

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
});

pub fn return_tag(name: String, content: []u8) Tag {
    const start: u16 = name.start;
    const end: u16 = @as(u16, name.start) + @as(u16, name.length);

    const tag_name = content[start..end];

    if (std.mem.eql(u8, tag_name, "html")) {
        return .html;
    }

    if (std.mem.eql(u8, tag_name, "body")) {
        return .body;
    }

    if (std.mem.eql(u8, tag_name, "div")) {
        return .div;
    }

    if (std.mem.eql(u8, tag_name, "h1")) {
        return .h1;
    }
    if (std.mem.eql(u8, tag_name, "em")) {
        return .em;
    }

    if (std.mem.eql(u8, tag_name, "br")) {
        return .br;
    }

    if (std.mem.eql(u8, tag_name, "hr")) {
        return .hr;
    }

    if (std.mem.eql(u8, tag_name, "title")) {
        return .title;
    }

    if (std.mem.eql(u8, tag_name, "p")) {
        return .p;
    }
    if (std.mem.eql(u8, tag_name, "a")) {
        return .a;
    }

    if (std.mem.eql(u8, tag_name, "b")) {
        return .b;
    }

    if (std.mem.eql(u8, tag_name, "span")) {
        return .span;
    }

    if (std.mem.eql(u8, tag_name, "button")) {
        return .button;
    }

    return .dead;
}

pub fn return_attribute_key() AttributeKey {}

pub fn return_attribute_value() AttributeValue {}

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

            // Text ends when we encounter '<'
            if (character == '<') {
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
        std.debug.print("Current character:{d}\n", .{self.content[self.current_position]});
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
            // I think the last one would overflow
            if (self.child_number > 0) {
                self.child_number -= 1;
            }

            return;
        }

        const tag_name_string = self.parse_name();
        const tag_name = self.content[tag_name_string.start..(tag_name_string.start + tag_name_string.length)];

        node.tag = static_string_map_tag.get(tag_name) orelse .dead;

        //node.tag = return_tag(tag_name, self.content[0..]);
        if (node.tag != .dead) {
            node.id_parent = self.child_number;
            node.id_node = self.node_number;

            self.child_number += 1;
            self.node_number += 1;

            dom_nodes.nodes[dom_nodes.nodes_size] = node;
            dom_nodes.nodes_size += 1;
        }

        // For now, skip everything until '>'.
        while (!self.eof()) {
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
            if (self.child_number > 0) {
                self.child_number -= 1;
            }
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
                node.id_parent = self.child_number;
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

pub fn draw_fancy_node_structure(parser: *HTMlParser) void {
    std.debug.print("==================Fancy Node Structure===============\n", .{});
    var number: u8 = 0;
    while (number < dom_nodes.nodes_size) {
        const node = dom_nodes.nodes[number];

        number += 1;

        var i: u8 = 0;
        while (i < node.id_parent) {
            std.debug.print(" |", .{});
            i += 1;
        }
        const start = node.text.start;
        const end = start + node.text.length;
        if (node.tag == .text) {
            std.debug.print("-  \"{s}\" ", .{parser.*.content[start..end]});
        } else {
            std.debug.print("-{s}", .{
                @tagName(node.tag),
            });
        }
        std.debug.print("\n", .{});
    }
}

pub fn draw_fancy_node_with_css_attributes() void {
    std.debug.print("==========================CSS Attributes==============\n", .{});
}

// assume unit is px
// colors will be in hex
const CSSParser = struct {
    // make a attributes struct for each element
    // and the copy it to every node that has that element
    content: [FILE_SIZE_BYTES_MAXIMUM]u8 = undefined,

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
            std.debug.print("Character: {c}", .{character});
            unreachable;
        }

        self.current_position += 1;
    }

    pub fn parse_tag(self: *CSSParser) Tag {
        const start = self.current_position;
        var length: u16 = 0;

        while (!self.eof()) {
            const character =
                self.content[self.current_position];

            if (!std.ascii.isAlphabetic(character)) {
                break;
            }

            self.current_position += 1;
            length += 1;
        }

        // return return_tag(String{ .start = start, .length = length }, self.content[0..]);

        return static_string_map_tag.get(self.content[start..(start + length)]) orelse .dead;
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

    pub fn parse_attribute(self: *CSSParser) String {
        const start = self.current_position;
        var length: u16 = 0;

        while (!self.eof()) {
            const character =
                self.content[self.current_position];

            // background-color
            if (!std.ascii.isAlphabetic(character)) {
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

    pub fn parse_value(self: *CSSParser) String {
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

    fn parse(self: *CSSParser) void {
        // 5 attributes
        //var attributes: Attributes = .{};

        while (!self.eof()) {
            // parse tag
            const tag: Tag = self.parse_tag();
            self.expect_character('{');
            while (!self.starts_with_char('}')) {
                const attribute = self.parse_attribute();
                self.expect_character(':');
                const value = self.parse_value();
                self.expect_character(';');

                const attribute_start = attribute.start;
                const attribute_end = attribute.start + attribute.length;

                const value_start = value.start;
                const value_end = value.start + value.length;

                std.debug.print("Tag: {s} - Attribute: {s} - Value:{s} \n", .{
                    @tagName(tag),
                    self.content[attribute_start..attribute_end],
                    self.content[value_start..value_end],
                });
            }
            self.expect_character('}');
        }
    }
};

pub fn main() anyerror!void {
    var html_parser: HTMlParser = .{};
    var css_parser: CSSParser = .{};

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

    // Only do the debug print stuff if in debug mode
    if (builtin.mode == .Debug) {
        std.debug.print("==============HTML Content============\n{s}\n", .{html_parser.content[0..html_parser.length_content]});

        std.debug.print("The nodes are:\n", .{});

        var i: u8 = 0;

        while (i < dom_nodes.nodes_size) : (i += 1) {
            const node = dom_nodes.nodes[i];
            const start: usize = node.text.start;
            const end: usize = start + node.text.length;

            std.debug.print("Node {d}: tag={s}, id={d}, text={s}, node_number={d}, child_number={d}\n", .{
                i,
                @tagName(node.tag),
                node.id.length,
                html_parser.content[start..end],
                node.id_node,
                node.id_parent,
            });
        }

        draw_fancy_node_structure(&html_parser);

        std.debug.print("==============CSS Content============\n{s}\n", .{css_parser.content[0..css_parser.length_content]});

        draw_fancy_node_with_css_attributes();
    }

    win.Create();
}
