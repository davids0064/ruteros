import { Body, Controller, Post, Query } from '@nestjs/common';
import { UploadsService } from './uploads.service';
import { MembershipService } from '../auth/membership.service';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { DomainException } from '../common/errors/domain.exception';
import type { AuthenticatedUser } from '../auth/jwt-payload';
import { PresignRequest, type PresignResponse } from './dto/upload.dto';

/**
 * 04 §2.10 — Uploads.
 *
 * `objectKey` incluye `{gymId}` por contrato (§5). Los scopes de boulder lo
 * toman de `?gymId=` (exigiendo membresía); los personales lo derivan del
 * usuario, de modo que un avatar queda bajo `user_avatar/{userId}/`.
 */
@Controller('uploads')
export class UploadsController {
  constructor(
    private readonly uploads: UploadsService,
    private readonly memberships: MembershipService,
  ) {}

  @Post('presign')
  async presign(
    @Body() body: PresignRequest,
    @CurrentUser() user: AuthenticatedUser,
    @Query('gymId') gymId?: string,
  ): Promise<PresignResponse> {
    if (body.scope === 'user_avatar') {
      return this.uploads.presign(body, user.id);
    }

    if (!gymId) {
      throw new DomainException(
        'VALIDATION_FAILED',
        'El scope indicado exige el parámetro `gymId`.',
      );
    }
    await this.memberships.assertAuthorizedMember(user, gymId);
    return this.uploads.presign(body, gymId);
  }
}
