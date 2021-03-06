/*
  Copyright 2018 EmmmHackers

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
  --------------------------
  File: physics.h
  Project: EmmmCS
  File Created: 2018-12-22 20:30:47
  Author: Chen Haodong (easyai@outlook.com)
  --------------------------
  Last Modified: 2018-12-23 20:44:05
  Modified By: Chen Haodong (easyai@outlook.com)
 */

#ifndef GAME_PB_PHYSICS_H
#define GAME_PB_PHYSICS_H

#include "objects.h"

//gravity acceleration
#define PB_PHY_G 1
typedef struct pb_rigid_body_t
{
    int x_speed;
    int y_speed;
    sprite_t spr;
} pb_rigid_body_t;

void pb_rigid_body_create(u8 idx, u8 x_s, u8 y_s, u8 w, u8 l, s8 x, s8 y, u8 p_w, u8 p_l, s8 p_x, s8 p_y);
void pb_rigid_body_destroy(pb_rigid_body_t *body);
void pb_physics_update(pb_rigid_body_t *bodys);
extern pb_rigid_body_t rigid_bodys[9];
#endif