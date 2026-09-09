import { Body, Controller, Get, HttpCode, Patch, Post } from '@nestjs/common';
import { AuthService } from './auth.service';
import { Public } from '../common/decorators/public.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import type { AuthenticatedUser } from './jwt-payload';
import {
  LoginPayload,
  RefreshPayloadDto,
  RegisterPayload,
  UpdateProfilePayload,
  type AuthSessionDTO,
  type UserProfileDTO,
} from './dto/auth.dto';

/** 04 §2.3 — Módulo Auth */
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Post('register')
  register(@Body() body: RegisterPayload): Promise<AuthSessionDTO> {
    return this.auth.register(body);
  }

  @Public()
  @Post('login')
  @HttpCode(200)
  login(@Body() body: LoginPayload): Promise<AuthSessionDTO> {
    return this.auth.login(body);
  }

  @Public()
  @Post('refresh')
  @HttpCode(200)
  refresh(@Body() body: RefreshPayloadDto): Promise<AuthSessionDTO> {
    return this.auth.refresh(body.refreshToken);
  }

  @Get('me')
  me(@CurrentUser() user: AuthenticatedUser): Promise<UserProfileDTO> {
    return this.auth.getProfile(user.id);
  }

  @Patch('me')
  updateMe(
    @CurrentUser() user: AuthenticatedUser,
    @Body() body: UpdateProfilePayload,
  ): Promise<UserProfileDTO> {
    return this.auth.updateProfile(user.id, body);
  }
}
