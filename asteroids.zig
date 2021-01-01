const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL2_gfxPrimitives.h");
    @cInclude("SDL2/SDL2_framerate.h");
});

const window_size = .{ 1200, 800 };
const window_width = window_size[0];
const window_height = window_size[1];

const max_asteroids = 400;
const Asteroid = struct {
    circle: Circle,
    velocity: [2]f32,
};
var asteroids = blk: {
    var init: [max_asteroids]?Asteroid = undefined;
    for (init) |*asteroid| {
        asteroid.* = null;
    }
    break :blk init;
};
const SpaceError = error{NoRoom};
fn doAsteroidBulletCollision(dt: f32) SpaceError!void {
    var collided = false;
    defer {
        if (collided) {
            std.debug.assert(bullet == null);
        }
    }
    var no_new_asteroids: i32 = 0;
    if (bullet) |the_bullet| {
        var path_segment = Segment{
            .start = the_bullet.position,
            .delta = mul(dt, the_bullet.velocity),
        };
        for (asteroids) |*maybe_asteroid| {
            if (maybe_asteroid.*) |*asteroid| {
                if (circleSegmentTorusIntersects(asteroid.circle, path_segment)) {
                    if (asteroid.circle.radius < 10) {
                        maybe_asteroid.* = null;
                        bullet = null;
                    } else {
                        // 1/2 (r^2) (v^2) = (r^2/4)(v'^2)
                        // 2 (v^2) = (v'^2)
                        // 2^1/2 = v'/v
                        const radius = asteroid.circle.radius;
                        const velocity = asteroid.velocity;
                        const angle = std.math.tau / 8.0;
                        const factor = std.math.sqrt(2.0);
                        asteroid.circle.radius = radius / 2;
                        asteroid.velocity = rotate_vector(velocity, -angle);
                        asteroid.velocity = mul(factor, asteroid.velocity);
                        var new_asteroid = Asteroid{
                            .circle = asteroid.circle,
                            .velocity = mul(factor, rotate_vector(velocity, angle)),
                        };
                        for (asteroids) |*maybe_free_asteroid| {
                            if (maybe_free_asteroid.* == null) {
                                maybe_free_asteroid.* = new_asteroid;
                                bullet = null;
                                return;
                            }
                        }
                        maybe_asteroid.* = null;
                        bullet = null;
                        return error.NoRoom;
                    }
                }
            }
        }
    }
}

const max_bullets = 10;
const Bullet = struct {
    position: [2]f32,
    velocity: [2]f32,
};
var bullet: ?Bullet = null;

const Player = struct {
    circle: Circle,
    angle: f32,
    velocity: [2]f32,
    damaged: bool,
    fn rotate(player: *Player, angle: f32, dt: f32) void {
        player.angle += angle * dt;
        player.angle = @mod(player.angle, std.math.tau);
        if (player.angle < 0.0) player.angle += std.math.tau;
    }
    fn shoot(player: *Player) void {
        var u = [2]f32{
            std.math.cos(player.angle),
            std.math.sin(player.angle),
        };
        var v = mul(player.circle.radius, u);
        var eye_position = add(player.circle.center, v);
        bullet = Bullet{ .position = eye_position, .velocity = mul(1000, u) };
    }
    fn render(player: *Player) SdlError!void {
        var eye_position = add(player.circle.center, polarVector(player.circle.radius, player.angle));
        const delta = 1.0 / 4.0 + 1.0 / 8.0;
        var left_wing = add(player.circle.center, polarVector(player.circle.radius, player.angle + delta * std.math.tau));
        var right_wing = add(player.circle.center, polarVector(player.circle.radius, player.angle - delta * std.math.tau));
        var points = [_][2]f32{ eye_position, left_wing, right_wing };

        var color: struct {
            r: u8,
            g: u8,
            b: u8,
        } = .{ .r = 0, .g = 255, .b = 0 };
        if (player.damaged) {
            color = .{
                .r = 255,
                .g = 0,
                .b = 0,
            };
        }
        inline for (.{ 0, 1, 2 }) |i| {
            inline for (.{ 0, 1, 2 }) |j| {
                if (i < j) {
                    try renderLineTorus(points[i], points[j], .{ .r = color.r, .g = color.g, .b = color.b });
                }
            }
        }
        try renderCircleTorus(player.circle, .{ .r = 255, .g = 255, .b = 0 });
        if (bullet) |real_bullet| {
            try renderCircleTorus(Circle{ .center = real_bullet.position, .radius = 5 }, .{ .r = 255, .g = 255, .b = 0 });
        }
    }

    fn push(player: *Player, dt: f32, mag: f32) void {
        var u = [2]f32{ std.math.cos(player.angle), std.math.sin(player.angle) };
        player.velocity = add(player.velocity, mul(dt * mag, u));
    }

    fn move(player: *Player, dt: f32) void {
        player.circle.center = donut(add(player.circle.center, mul(dt, player.velocity)));
        const velocity_magnitude = magnitude(player.velocity);
        if (velocity_magnitude < 0.00001) {
            player.velocity = [2]f32{ 0, 0 };
        } else {
            const friction = 100.0;
            const friction_velocity_magnitude = std.math.max(0, velocity_magnitude - dt * friction);
            player.velocity = mul(friction_velocity_magnitude / velocity_magnitude, player.velocity);
        }
        if (bullet) |*real_bullet| {
            real_bullet.position = add(real_bullet.position, mul(dt, real_bullet.velocity));
            if (real_bullet.position[0] < 0 or real_bullet.position[0] > window_width or
                real_bullet.position[1] < 0 or real_bullet.position[1] > window_height)
                bullet = null;
        }
    }
};
var playerOne = Player{
    .circle = Circle{
        .center = [2]f32{ 400, 400 },
        .radius = 12,
    },
    .angle = 0.0,
    .velocity = [2]f32{ 0, 0 },
    .damaged = false,
};
fn polarVector(mag: f32, angle: f32) [2]f32 {
    return [2]f32{
        mag * std.math.cos(angle),
        mag * std.math.sin(angle),
    };
}
fn renderCircleTorus(circle: Circle, color: struct { r: u8, g: u8, b: u8 }) SdlError!void {
    inline for (.{ -1, 0, 1 }) |dx| {
        inline for (.{ -1, 0, 1 }) |dy| {
            if (dx == 0 or dy == 0) {
                var x: i16 = @floatToInt(i16, circle.center[0] + dx * window_width);
                var y: i16 = @floatToInt(i16, circle.center[1] + dy * window_height);
                var r: i16 = @floatToInt(i16, circle.radius);
                if (sdl.circleRGBA(renderer, x, y, r, color.r, color.g, color.b, 255) != 0)
                    return error.SdlError;
            }
        }
    }
}
fn renderLineTorus(start: [2]f32, end: [2]f32, color: struct { r: u8, g: u8, b: u8 }) SdlError!void {
    inline for (.{ -1, 0, 1 }) |dx| {
        inline for (.{ -1, 0, 1 }) |dy| {
            if (dx == 0 or dy == 0) {
                var sx: i16 = @floatToInt(i16, start[0] + dx * window_width);
                var sy: i16 = @floatToInt(i16, start[1] + dy * window_height);
                var ex: i16 = @floatToInt(i16, end[0] + dx * window_width);
                var ey: i16 = @floatToInt(i16, end[1] + dy * window_height);
                if (sdl.lineRGBA(renderer, sx, sy, ex, ey, color.r, color.g, color.b, 255) != 0)
                    return error.SdlError;
            }
        }
    }
}
fn circleSegmentTorusIntersects(c: Circle, s: Segment) bool {
    inline for (.{ -1, 0, 1 }) |c_dx| {
        inline for (.{ -1, 0, 1 }) |c_dy| {
            if (c_dx == 0 or c_dy == 0) {
                inline for (.{ -1, 0, 1 }) |s_dx| {
                    inline for (.{ -1, 0, 1 }) |s_dy| {
                        if (s_dx == 0 or s_dy == 0) {
                            if (intersects(Circle{ .center = add(c.center, [2]f32{ c_dx * window_width, c_dy * window_height }), .radius = c.radius }, Segment{ .start = add(s.start, [2]f32{ s_dx * window_width, s_dy * window_height }), .delta = s.delta }))
                                return true;
                        }
                    }
                }
            }
        }
    }
    return false;
}
fn circleTorusIntersects(c1: Circle, c2: Circle) bool {
    inline for (.{ -1, 0, 1 }) |c_dx| {
        inline for (.{ -1, 0, 1 }) |c_dy| {
            if (c_dx == 0 or c_dy == 0) {
                inline for (.{ -1, 0, 1 }) |s_dx| {
                    inline for (.{ -1, 0, 1 }) |s_dy| {
                        if (s_dx == 0 or s_dy == 0) {
                            var c1p = Circle{ .center = add(c1.center, [2]f32{ c_dx * window_width, c_dy * window_height }), .radius = c1.radius };
                            var c2p = Circle{ .center = add(c2.center, [2]f32{ s_dx * window_width, s_dy * window_height }), .radius = c2.radius };
                            if (c1p.intersects(c2p))
                                return true;
                        }
                    }
                }
            }
        }
    }
    return false;
}

inline fn square_distance(a: [2]f32, b: [2]f32) f32 {
    const dx = a[0] - b[0];
    const dy = a[1] - b[1];
    return dx * dx + dy * dy;
}

inline fn magnitude(a: [2]f32) f32 {
    return std.math.sqrt(dot(a, a));
}

inline fn dot(a: [2]f32, b: [2]f32) f32 {
    return a[0] * b[0] + a[1] * b[1];
}

inline fn sub(a: [2]f32, b: [2]f32) [2]f32 {
    return [2]f32{ a[0] - b[0], a[1] - b[1] };
}

fn donut(v: [2]f32) [2]f32 {
    var w: [2]f32 = v;
    inline for (.{ 0, 1 }) |i| {
        if (w[i] >= window_size[i]) {
            w[i] -= window_size[i];
        } else if (w[i] < 0) {
            w[i] += window_size[i];
        }
    }
    return w;
}

inline fn mul(k: f32, a: [2]f32) [2]f32 {
    return [2]f32{ k * a[0], k * a[1] };
}

inline fn add(a: [2]f32, b: [2]f32) [2]f32 {
    return [2]f32{ a[0] + b[0], a[1] + b[1] };
}

fn distance(a: [2]f32, b: [2]f32) f32 {
    return std.math.sqrt(square_distance(a, b));
}

fn rotate_vector(v: [2]f32, angle: f32) [2]f32 {
    const u = [2]f32{ std.math.cos(angle), std.math.sin(angle) };
    return [2]f32{ u[0] * v[0] - u[1] * v[1], u[0] * v[1] + u[1] * v[0] };
}

const Circle = struct {
    center: [2]f32,
    radius: f32,
    fn contains(a: Circle, point: [2]f32) bool {
        const dx = a.center[0] - point[0];
        const dy = a.center[1] - point[1];
        return dx * dx + dy * dy;
    }
    fn intersects(a: Circle, b: Circle) bool {
        return square_distance(a.center, b.center) <= (a.radius + b.radius) * (a.radius + b.radius);
    }
};

const Segment = struct {
    start: [2]f32,
    delta: [2]f32,
    fn square_distance_to(segment: Segment, point: [2]f32) f32 {
        const t = std.math.min(1, std.math.max(0, dot(segment.delta, sub(point, segment.start)) / dot(segment.delta, segment.delta)));
        return square_distance([2]f32{
            segment.start[0] + t * segment.delta[0],
            segment.start[1] + t * segment.delta[1],
        }, point);
    }
};

fn intersects(circle: Circle, segment: Segment) bool {
    return segment.square_distance_to(circle.center) <= circle.radius * circle.radius;
}

const SdlError = error{SdlError};

var window: *sdl.SDL_Window = undefined;
var renderer: *sdl.SDL_Renderer = undefined;
var key_state: ?[*]const u8 = undefined;

fn setup() void {
    asteroids[0] = Asteroid{
        .circle = Circle{
            .center = [2]f32{ 400, 400 },
            .radius = 80,
        },
        .velocity = [2]f32{ 40, 60 },
    };
}
pub fn main() SdlError!void {
    setup();
    key_state = sdl.SDL_GetKeyboardState(null);
    window = sdl.SDL_CreateWindow("retro-redo: asteroids", sdl.SDL_WINDOWPOS_CENTERED, sdl.SDL_WINDOWPOS_CENTERED, window_width, window_height, sdl.SDL_WINDOW_SHOWN) orelse return error.SdlError;
    defer sdl.SDL_DestroyWindow(window);

    renderer = sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_ACCELERATED) orelse return error.SdlError;
    defer sdl.SDL_DestroyRenderer(renderer);

    var fps_manager: sdl.FPSmanager = undefined;
    sdl.SDL_initFramerate(&fps_manager);
    const fps = 200;
    if (sdl.SDL_setFramerate(&fps_manager, fps) != 0) {
        std.debug.print("SdlError: {}\n", .{@as([*:0]const u8, sdl.SDL_GetError())});
        return error.SdlError;
    }

    while (!process_events()) {
        _ = sdl.SDL_framerateDelay(&fps_manager);
        std.debug.print("FPS = {}\n", .{sdl.SDL_getFramerate(&fps_manager)});
        tick(1.0 / @intToFloat(f32, fps));
        try render();
    }
}

fn process_events() bool {
    var event: sdl.SDL_Event = undefined;
    while (sdl.SDL_PollEvent(&event) != 0) {
        switch (event.type) {
            sdl.SDL_QUIT => return true,
            sdl.SDL_KEYDOWN => {
                if (@enumToInt(event.key.keysym.scancode) == sdl.SDL_SCANCODE_SPACE) {
                    playerOne.shoot();
                }
            },
            else => {},
        }
    }
    return false;
}

fn tick(dt: f32) void {
    if (key_state.?[sdl.SDL_SCANCODE_W] != 0) playerOne.push(dt, 500.0);
    if (key_state.?[sdl.SDL_SCANCODE_S] != 0) playerOne.push(dt, -500.0);
    if (key_state.?[sdl.SDL_SCANCODE_D] != 0) playerOne.rotate(5, dt);
    if (key_state.?[sdl.SDL_SCANCODE_A] != 0) playerOne.rotate(-5, dt);
    playerOne.move(dt);
    playerOne.damaged = false;
    for (asteroids) |*maybe_asteroid| {
        if (maybe_asteroid.*) |*asteroid| {
            asteroid.circle.center = donut(add(asteroid.circle.center, mul(dt, asteroid.velocity)));
            if (asteroid.circle.intersects(playerOne.circle))
                playerOne.damaged = true;
        }
    }
    doAsteroidBulletCollision(dt) catch |collision_error| switch (collision_error) {
        SpaceError.NoRoom => {
            std.debug.print("There was no room for other asteroid\n", .{});
        },
        else => {},
    };
}

fn render() SdlError!void {
    if (sdl.SDL_SetRenderDrawColor(renderer, 0, 0, 64, 255) != 0)
        return error.SdlError;
    if (sdl.SDL_RenderClear(renderer) != 0)
        return error.SdlError;
    try playerOne.render();
    for (asteroids) |maybe_asteroid| {
        if (maybe_asteroid) |asteroid| {
            try renderCircleTorus(asteroid.circle, .{ .r = 255, .g = 255, .b = 255 });
        }
    }
    sdl.SDL_RenderPresent(renderer);
}
