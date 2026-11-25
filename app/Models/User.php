<?php

/*
 * This file is part of Cachet.
 *
 * (c) Alt Three Services Limited
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

namespace App\Models;

use Cachet\Models\User as CachetUser;

/**
 * The core model already brings API tokens, notifications, MFA, the
 * preferred locale and permission groups, so the app only names it.
 */
class User extends CachetUser {}
