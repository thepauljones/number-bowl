#import "Basic";
#import "Math";
#import "String";
#import "System";
#import "Window_Creation";
Input :: #import "Input";
Simp  :: #import "Simp";

// ─── Colors ────────────────────────────────────────────────────────────────

hex_color :: (r: u8, g: u8, b: u8) -> Vector4 {
    return .{r / 255.0, g / 255.0, b / 255.0, 1.0};
}

COLOR_BG       :: #run hex_color(0xFA, 0xF6, 0xF1);
COLOR_OUTLINE  :: #run hex_color(0x9E, 0x9A, 0x95);
COLOR_SUCCESS  :: #run hex_color(0xD4, 0xAA, 0x4A);

DOT_COLORS :: Vector4.[
    #run hex_color(0xE8, 0x94, 0x4A),  // orange
    #run hex_color(0x5B, 0x8D, 0xAE),  // blue
    #run hex_color(0xE8, 0xA0, 0xB4),  // pink
    #run hex_color(0x8B, 0xAA, 0x5A),  // green
    #run hex_color(0xE8, 0xC8, 0x4A),  // yellow
    #run hex_color(0xD4, 0x79, 0x6A),  // coral
];

// ─── Physics Constants ────────────────────────────────────────────────────

GRAVITY     :: 800.0;  // pixels/s² downward
DAMPING     :: 0.98;   // velocity multiplier per step
RESTITUTION :: 0.65;   // bounciness on collision

// ─── Game State ────────────────────────────────────────────────────────────

MAX_BOWL_DOTS :: 5;
MAX_POOL_DOTS :: 6;

Bowl_Dot :: struct {
    active: bool;
    color:  Vector4;
    pos:    Vector2;
    vel:    Vector2;
}

Game_State :: struct {
    goal_number:    int;
    bowl_dots:      [MAX_BOWL_DOTS] Bowl_Dot;
    bowl_dot_count: int;

    hand_dots:      [MAX_POOL_DOTS] Vector4;
    hand_dot_count: int;

    pool_dots:      [MAX_POOL_DOTS] bool;  // true = still available
    pool_dot_count: int;
}

// ─── Particles ─────────────────────────────────────────────────────────────

Particle :: struct {
    pos:   Vector2;
    vel:   Vector2;
    life:  float;
    color: Vector4;
}

MAX_PARTICLES :: 64;

// ─── Globals ───────────────────────────────────────────────────────────────

my_window: Window_Type;
window_width:  s32 = 1280;
window_height: s32 = 960;

game: Game_State;
particles: [MAX_PARTICLES] Particle;
particle_count: int = 0;

my_font: *Simp.Dynamic_Font;
working_directory_set := false;

saved_window_info: Saved_Window_Info;
is_fullscreen := false;

current_time: float64;
last_time: float64;
dt: float;

success_glow_timer: float = 0;
just_succeeded := false;

// ─── Circle Drawing ───────────────────────────────────────────────────────

draw_filled_circle :: (cx: float, cy: float, radius: float, color: Vector4, segments: int = 48) {
    Simp.set_shader_for_color(true);
    step := TAU / cast(float) segments;
    center := Vector3.{cx, cy, 0};
    for i: 0..segments-1 {
        a0 := step * cast(float) i;
        a1 := step * cast(float) (i + 1);
        p0 := Vector3.{cx + cos(a0) * radius, cy + sin(a0) * radius, 0};
        p1 := Vector3.{cx + cos(a1) * radius, cy + sin(a1) * radius, 0};
        Simp.immediate_triangle(center, p0, p1, color, color, color);
    }
}

draw_circle_outline :: (cx: float, cy: float, radius: float, thickness: float, color: Vector4, segments: int = 64) {
    Simp.set_shader_for_color(true);
    step := TAU / cast(float) segments;
    inner := radius - thickness * 0.5;
    outer := radius + thickness * 0.5;
    for i: 0..segments-1 {
        a0 := step * cast(float) i;
        a1 := step * cast(float) (i + 1);
        c0 := cos(a0);  s0 := sin(a0);
        c1 := cos(a1);  s1 := sin(a1);
        p0 := Vector2.{cx + c0 * inner, cy + s0 * inner};
        p1 := Vector2.{cx + c1 * inner, cy + s1 * inner};
        p2 := Vector2.{cx + c1 * outer, cy + s1 * outer};
        p3 := Vector2.{cx + c0 * outer, cy + s0 * outer};
        Simp.immediate_quad(p0, p1, p2, p3, color);
    }
}

// ─── Layout Helpers ────────────────────────────────────────────────────────

get_bowl_center :: () -> Vector2 {
    return .{cast(float) window_width * 0.5, cast(float) window_height * 0.52};
}

get_bowl_radius :: () -> float {
    return cast(float) window_height * 0.25;
}

get_dot_radius :: () -> float {
    return cast(float) window_height * 0.032;
}

get_hand_radius :: () -> float {
    return cast(float) window_height * 0.035;
}

get_pool_y :: () -> float {
    return cast(float) window_height * 0.08;
}

get_pool_dot_positions :: () -> [MAX_POOL_DOTS] Vector2 {
    result: [MAX_POOL_DOTS] Vector2;
    y := get_pool_y();
    w := cast(float) window_width;
    total_width := w * 0.6;
    start_x := (w - total_width) * 0.5;
    spacing := total_width / cast(float)(MAX_POOL_DOTS - 1);
    for i: 0..MAX_POOL_DOTS-1 {
        result[i] = .{start_x + spacing * cast(float) i, y};
    }
    return result;
}

// ─── Game Logic ────────────────────────────────────────────────────────────

init_game :: () {
    game.goal_number = 3;
    game.bowl_dot_count = 0;
    game.hand_dot_count = 0;
    game.pool_dot_count = MAX_POOL_DOTS;

    for i: 0..MAX_BOWL_DOTS-1 {
        game.bowl_dots[i].active = false;
    }
    for i: 0..MAX_POOL_DOTS-1 {
        game.pool_dots[i] = true;
    }

    particle_count = 0;
    success_glow_timer = 0;
    just_succeeded = false;
}

new_round :: () {
    old_goal := game.goal_number;
    new_goal := old_goal;
    // Cycle through 1-5
    while new_goal == old_goal {
        new_goal = (old_goal % 5) + 1;
    }
    game.goal_number = new_goal;
    game.bowl_dot_count = 0;
    game.hand_dot_count = 0;
    game.pool_dot_count = MAX_POOL_DOTS;

    for i: 0..MAX_BOWL_DOTS-1 {
        game.bowl_dots[i].active = false;
    }
    for i: 0..MAX_POOL_DOTS-1 {
        game.pool_dots[i] = true;
    }

    success_glow_timer = 0;
    just_succeeded = false;
}

spawn_success_particles :: () {
    bowl := get_bowl_center();
    r := get_bowl_radius();
    count := 18;
    for i: 0..count-1 {
        if particle_count >= MAX_PARTICLES break;
        angle := TAU * cast(float) i / cast(float) count;
        px := bowl.x + cos(angle) * r;
        py := bowl.y + sin(angle) * r;
        speed := cast(float) window_height * 0.05;
        p := *particles[particle_count];
        p.pos = .{px, py};
        p.vel = .{cos(angle) * speed, sin(angle) * speed};
        p.life = 1.0;
        ci := i % DOT_COLORS.count;
        p.color = DOT_COLORS[ci];
        particle_count += 1;
    }
}

handle_click :: (mx: float, my: float) {
    dot_r := get_dot_radius();
    bowl_center := get_bowl_center();
    bowl_r := get_bowl_radius();

    // Always try picking up from pool (add to hand)
    {
        pool_positions := get_pool_dot_positions();
        for i: 0..MAX_POOL_DOTS-1 {
            if !game.pool_dots[i] continue;
            dx := mx - pool_positions[i].x;
            dy := my - pool_positions[i].y;
            dist := sqrt(dx*dx + dy*dy);
            if dist < dot_r * 2.0 && game.hand_dot_count < MAX_POOL_DOTS {
                game.pool_dots[i] = false;
                game.pool_dot_count -= 1;
                game.hand_dots[game.hand_dot_count] = DOT_COLORS[i];
                game.hand_dot_count += 1;
                return;
            }
        }
    }

    // Click on bowl
    dx := mx - bowl_center.x;
    dy := my - bowl_center.y;
    dist := sqrt(dx*dx + dy*dy);
    if dist < bowl_r {
        if game.hand_dot_count > 0 {
            // Place all hand dots into bowl
            bowl_spawn_center := get_bowl_center();
            bowl_spawn_r := get_bowl_radius();
            for i: 0..game.hand_dot_count-1 {
                if game.bowl_dot_count >= MAX_BOWL_DOTS break;
                // Find next free bowl slot
                for j: 0..MAX_BOWL_DOTS-1 {
                    if !game.bowl_dots[j].active {
                        game.bowl_dots[j].active = true;
                        game.bowl_dots[j].color = game.hand_dots[i];
                        // Spread dots across the top of the bowl
                        spread := get_dot_radius() * 2.5;
                        center_offset := cast(float)(game.hand_dot_count - 1) * 0.5;
                        offset := (cast(float) i - center_offset) * spread;
                        game.bowl_dots[j].pos.x = bowl_spawn_center.x + offset;
                        game.bowl_dots[j].pos.y = bowl_spawn_center.y + bowl_spawn_r * 0.6;
                        game.bowl_dots[j].vel = .{0, 0};
                        game.bowl_dot_count += 1;
                        break;
                    }
                }
            }
            game.hand_dot_count = 0;
            // Check success
            if game.bowl_dot_count == game.goal_number {
                just_succeeded = true;
                success_glow_timer = 2.5;
                spawn_success_particles();
            }
        } else if game.bowl_dot_count > 0 {
            // Hand empty — pick up closest dot to click
            best_i := -1;
            best_dist := 999999.0;
            for i: 0..MAX_BOWL_DOTS-1 {
                if !game.bowl_dots[i].active continue;
                cdx := mx - game.bowl_dots[i].pos.x;
                cdy := my - game.bowl_dots[i].pos.y;
                d := sqrt(cdx*cdx + cdy*cdy);
                if d < best_dist {
                    best_dist = d;
                    best_i = i;
                }
            }
            if best_i >= 0 {
                game.hand_dots[0] = game.bowl_dots[best_i].color;
                game.hand_dot_count = 1;
                game.bowl_dots[best_i].active = false;
                game.bowl_dot_count -= 1;
                just_succeeded = false;
                success_glow_timer = 0;
                return;
            }
        }
    }
}

// ─── Update ────────────────────────────────────────────────────────────────

update_particles :: () {
    i := 0;
    while i < particle_count {
        p := *particles[i];
        p.life -= dt * 0.7;
        p.pos.x += p.vel.x * dt;
        p.pos.y += p.vel.y * dt;
        p.vel.x *= 0.97;
        p.vel.y *= 0.97;
        if p.life <= 0 {
            // Swap with last
            particles[i] = particles[particle_count - 1];
            particle_count -= 1;
        } else {
            i += 1;
        }
    }
}

update_bowl_physics :: () {
    bowl_center := get_bowl_center();
    bowl_r := get_bowl_radius();
    dot_r := get_dot_radius();

    for i: 0..MAX_BOWL_DOTS-1 {
        if !game.bowl_dots[i].active continue;
        d := *game.bowl_dots[i];

        // Gravity (y-up coordinate system)
        d.vel.y -= GRAVITY * dt;

        // Move
        d.pos.x += d.vel.x * dt;
        d.pos.y += d.vel.y * dt;

        // Bowl boundary collision
        dx := d.pos.x - bowl_center.x;
        dy := d.pos.y - bowl_center.y;
        dist := sqrt(dx*dx + dy*dy);
        if dist + dot_r > bowl_r {
            // Normal pointing from center to dot
            nx := dx / dist;
            ny := dy / dist;
            // Clamp position to inside bowl
            d.pos.x = bowl_center.x + nx * (bowl_r - dot_r);
            d.pos.y = bowl_center.y + ny * (bowl_r - dot_r);
            // Reflect velocity along normal
            vn := d.vel.x * nx + d.vel.y * ny;
            if vn > 0 {
                d.vel.x -= (1.0 + RESTITUTION) * vn * nx;
                d.vel.y -= (1.0 + RESTITUTION) * vn * ny;
            }
        }

        // Damping
        d.vel.x *= DAMPING;
        d.vel.y *= DAMPING;
    }

    // Dot-dot collisions
    dot_diameter := dot_r * 2.0;
    for i: 0..MAX_BOWL_DOTS-1 {
        if !game.bowl_dots[i].active continue;
        for j: i+1..MAX_BOWL_DOTS-1 {
            if !game.bowl_dots[j].active continue;
            a := *game.bowl_dots[i];
            b := *game.bowl_dots[j];
            dx := b.pos.x - a.pos.x;
            dy := b.pos.y - a.pos.y;
            dist := sqrt(dx*dx + dy*dy);
            if dist < dot_diameter && dist > 0.001 {
                // Push apart
                overlap := (dot_diameter - dist) * 0.5;
                nx := dx / dist;
                ny := dy / dist;
                a.pos.x -= nx * overlap;
                a.pos.y -= ny * overlap;
                b.pos.x += nx * overlap;
                b.pos.y += ny * overlap;

                // Exchange velocity along collision normal
                avn := a.vel.x * nx + a.vel.y * ny;
                bvn := b.vel.x * nx + b.vel.y * ny;
                a.vel.x += (bvn - avn) * RESTITUTION * nx;
                a.vel.y += (bvn - avn) * RESTITUTION * ny;
                b.vel.x += (avn - bvn) * RESTITUTION * nx;
                b.vel.y += (avn - bvn) * RESTITUTION * ny;
            }
        }
    }
}

// ─── Rendering ─────────────────────────────────────────────────────────────

draw_frame :: () {
    Simp.clear_render_target(COLOR_BG.x, COLOR_BG.y, COLOR_BG.z, 1.0);
    Simp.set_shader_for_color(true);

    bowl_center := get_bowl_center();
    bowl_r := get_bowl_radius();
    dot_r := get_dot_radius();

    // Draw bowl
    outline_color := COLOR_OUTLINE;
    if just_succeeded {
        // Lerp toward gold
        t := clamp(success_glow_timer / 2.5, 0.0, 1.0);
        outline_color = lerp(COLOR_OUTLINE, COLOR_SUCCESS, t);
    } else if game.bowl_dot_count > game.goal_number {
        // Dim outline
        outline_color.w = 0.4;
    }
    thickness := cast(float) window_height * 0.005;
    draw_circle_outline(bowl_center.x, bowl_center.y, bowl_r, thickness, outline_color);

    // Draw dots inside bowl at physics positions
    for i: 0..MAX_BOWL_DOTS-1 {
        if !game.bowl_dots[i].active continue;
        draw_filled_circle(game.bowl_dots[i].pos.x, game.bowl_dots[i].pos.y, dot_r, game.bowl_dots[i].color);
    }

    // Draw goal number at top
    goal_y := cast(float) window_height * 0.88;
    goal_x := cast(float) window_width * 0.5;
    goal_circle_r := cast(float) window_height * 0.055;
    draw_circle_outline(goal_x, goal_y, goal_circle_r, thickness, COLOR_OUTLINE);

    if my_font {
        goal_text := tprint("%", game.goal_number);
        text_w := Simp.prepare_text(my_font, goal_text);
        tx := cast(s64)(goal_x) - text_w / 2;
        ty := cast(s64)(goal_y) - my_font.character_height / 3;
        Simp.draw_prepared_text(my_font, tx, ty, COLOR_OUTLINE);
    }

    // Draw pool dots at bottom
    Simp.set_shader_for_color(true);
    pool_positions := get_pool_dot_positions();
    for i: 0..MAX_POOL_DOTS-1 {
        if !game.pool_dots[i] continue;
        draw_filled_circle(pool_positions[i].x, pool_positions[i].y, dot_r, DOT_COLORS[i]);
    }

    // Draw particles
    for i: 0..particle_count-1 {
        p := *particles[i];
        c := p.color;
        c.w = clamp(p.life, 0.0, 1.0);
        pr := cast(float) window_height * 0.006;
        draw_filled_circle(p.pos.x, p.pos.y, pr, c, 16);
    }

    // Draw hand at mouse position
    mx, my, mouse_ok := get_mouse_pointer_position(my_window, true);
    if mouse_ok {
        hand_r := get_hand_radius();
        fmx := cast(float) mx;
        fmy := cast(float) my;

        if game.hand_dot_count == 1 {
            draw_filled_circle(fmx, fmy, dot_r, game.hand_dots[0]);
        } else if game.hand_dot_count > 1 {
            // Fan dots around cursor
            for i: 0..game.hand_dot_count-1 {
                angle := TAU * cast(float) i / cast(float) game.hand_dot_count - TAU * 0.25;
                fan_r := dot_r * 1.2;
                dx := cos(angle) * fan_r;
                dy := sin(angle) * fan_r;
                draw_filled_circle(fmx + dx, fmy + dy, dot_r * 0.8, game.hand_dots[i]);
            }
        }
        draw_circle_outline(fmx, fmy, hand_r, thickness * 0.7, COLOR_OUTLINE);
    }

    Simp.swap_buffers(my_window);
}

// ─── Font Init ─────────────────────────────────────────────────────────────

my_init_fonts :: () {
    if !working_directory_set {
        path := path_strip_filename(get_path_of_running_executable());
        set_working_directory(path);
        working_directory_set = true;
    }

    pixel_height := window_height / 12;
    my_font = Simp.get_font_at_size("data", "OpenSans-Regular.ttf", pixel_height);
    assert(my_font != null);
}

// ─── Main ──────────────────────────────────────────────────────────────────

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1);
    }

    my_window = create_window(window_width, window_height, "Number Bowl");

    window_width, window_height = Simp.get_render_dimensions(my_window);

    Simp.set_render_target(my_window);

    my_init_fonts();
    init_game();

    last_time = seconds_since_init();

    quit := false;
    while !quit {
        current_time = seconds_since_init();
        dt = cast(float)(current_time - last_time);
        if dt > 0.1 dt = 0.1;
        last_time = current_time;

        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);
            if it.window == my_window {
                should_reinit := (it.width != window_width) || (it.height != window_height);
                window_width  = it.width;
                window_height = it.height;
                if should_reinit my_init_fonts();
            }
        }

        for Input.events_this_frame {
            if it.type == .QUIT then quit = true;

            if it.type == .KEYBOARD {
                if it.key_pressed == 1 {
                    if it.key_code == .ESCAPE {
                        quit = true;
                    }

                    if it.key_code == .F11 {
                        is_fullscreen = !is_fullscreen;
                        success, w, h := toggle_fullscreen(my_window, is_fullscreen, *saved_window_info);
                        if success {
                            window_width = w;
                            window_height = h;
                            my_init_fonts();
                        }
                    }

                    if it.key_code == .MOUSE_BUTTON_LEFT {
                        mx, my, ok := get_mouse_pointer_position(my_window, true);
                        if ok {
                            handle_click(cast(float) mx, cast(float) my);
                        }
                    }
                }
            }
        }

        // Auto advance after success
        if just_succeeded {
            success_glow_timer -= dt;
            if success_glow_timer <= 0 {
                new_round();
            }
        }

        update_bowl_physics();
        update_particles();
        draw_frame();

        sleep_milliseconds(10);
        reset_temporary_storage();
    }
}

#run {
    #if OS == .WINDOWS {
        WR :: #import "Windows_Resources";
        WR.disable_runtime_console();
    }
}
