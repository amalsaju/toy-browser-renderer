const std = @import("std");
const win = @import("win.zig");

const ELEMENTS_MAXIMUM_NUMBER = 128;
const ATTRIBUTES_MAXIMUM_NUMBER = 256;
const TEXT_LENGTH_MAXIMUM_BYTES = 8192;
const CSS_STYLE_RULES_MAXIMUM_NUMBER = 64;

const FILE_SIZE_BYTES_MAXIMUM = 5 * 1024;

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

const Attributes = struct {
    position: Position = .{},
    background_color: u32,
    text_color: u32,
    margin: u16,
    padding: u16,
    width: u16,
    height: u16,
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

const HTMlParser = struct {
    content: [FILE_SIZE_BYTES_MAXIMUM]u8 = undefined,

    length_content: u32 = 0,

    current_position: u16 = 0,

    node_number: u8 = 0,
    child_number: u8 = 0,

    pub fn eof(self: *const HTMlParser) bool {
        return self.current_position >= self.length_content;
    }

    pub fn read_next_char(self: *const HTMlParser) ?u8 {
        if (self.current_position + 1 >= self.length_content) {
            return null;
        }

        return self.content[self.current_position + 1];
    }

    pub fn starts_with_char(
        self: *const HTMlParser,
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

    pub fn consume_character(self: *HTMlParser, char: u8) ?u8 {
        if (self.eof()) {
            return null;
        }

        const character = self.content[self.current_position];
        if (character == char) {
            self.current_position += 1;
            return;
        }

        return character;
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

        //self.print_current_character();
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

    pub fn return_tag(
        self: *const HTMlParser,
        name: String,
    ) Tag {
        const start: u16 = name.start;
        const end: u16 = @as(u16, name.start) + @as(u16, name.length);

        const tag_name = self.content[start..end];

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

        const tag_name = self.parse_name();

        node.tag = self.return_tag(tag_name);
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

// assume unit is px
// colors will be in hex
const CSSParser = struct {
    // make a attributes struct for each element
    // and the copy it to every node that has that element
    var attributes: Attributes = .{};

    fn parse_css() void {
        attributes.position = .{ 0, 0 };
        attributes.background_color = 0;
        attributes.text_color = 0;
        attributes.margin = 0;
        attributes.padding = 0;
        attributes.width = 0;
        attributes.height = 0;
    }
};

pub fn main() anyerror!void {
    var html_parser: HTMlParser = .{};

    html_parser.length_content = win.read_file(&html_parser.content, true);

    std.debug.print("==============HTML Content============\n{s}\n", .{html_parser.content[0..html_parser.length_content]});

    html_parser.parse();

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
    win.Create();
}
