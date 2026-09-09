import { Inject, Injectable } from '@nestjs/common';
import { KYSELY, type Db } from '../database/database.module';
import { DomainException, notFound } from '../common/errors/domain.exception';
import { InventoryService } from '../inventory/inventory.service';
import { GradesService } from '../grades/grades.service';
import { DIFFICULTY_CONSTANTS, DifficultyService } from './difficulty.service';
import type { HoldDTO } from '../inventory/dto/inventory.dto';
import type { HoldRoleEnum } from '../database/schema';
import type {
  GenerateRouteProposal,
  GenerateRouteRequest,
  PlacedHoldDTO,
} from './dto/route.dto';

const clamp = (v: number, min: number, max: number) => Math.min(Math.max(v, min), max);

/**
 * Motor de propuesta de bloques (RF-4.1, RF-4.2).
 *
 * NO persiste nada: devuelve una propuesta en RAM que el setter arrastra, gira
 * y reasigna en el lienzo 2D. Es la mitad "máquina" del human-in-the-loop.
 *
 * Reglas biomecánicas aplicadas, todas derivadas del motor de dificultad (§6):
 *   1. El número de presas crece con el grado objetivo.
 *   2. Se eligen las presas cuyo peso intrínseco acerca `hold_factor` al peso
 *      del grado pedido, descontando el desplome del muro.
 *   3. La separación media se despeja invirtiendo `span_factor`, de modo que la
 *      propuesta caiga sobre el grado objetivo por construcción.
 *   4. Trazado en zigzag ascendente: alternar el lado obliga a cruces de mano y
 *      evita la escalera vertical que ningún setter firmaría.
 */
@Injectable()
export class GeneratorService {
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly inventory: InventoryService,
    private readonly grades: GradesService,
    private readonly difficulty: DifficultyService,
  ) {}

  async generate(request: GenerateRouteRequest): Promise<GenerateRouteProposal> {
    const wall = await this.db
      .selectFrom('walls')
      .select(['id', 'gym_id', 'default_grade_system_id'])
      .where('id', '=', request.wallId)
      .executeTakeFirst();
    if (!wall) throw notFound('El muro');

    const scale = await this.grades.findValues(request.gradeSystemId);
    const target = scale.find((g) => g.id === request.targetGradeId);
    if (!target) {
      throw new DomainException(
        'GRADE_SYSTEM_MISMATCH',
        'El grado objetivo no pertenece al sistema de grados indicado.',
      );
    }

    const available = await this.inventory.findAvailableByGym(wall.gym_id, request.enabledSetIds);
    if (available.length < 2) {
      throw new DomainException(
        'HOLD_NOT_AVAILABLE',
        'No hay suficientes presas disponibles en los sets habilitados.',
      );
    }

    // Regla 1
    const holdCount = clamp(
      request.holdCount ?? 6 + Math.round(target.rankOrdinal / 2),
      2,
      Math.min(available.length, 20),
    );

    // Regla 2: el desplome ya aporta dificultad, así que rebaja el peso exigido
    // a los agarres.
    const inclineFactor =
      1 + (Math.max(request.wallInclineDeg, 0) / 90) * DIFFICULTY_CONSTANTS.INCLINE_WEIGHT;
    const desiredHoldFactor = target.weightFactor / inclineFactor;

    const chosen = this.pickHolds(available, holdCount, desiredHoldFactor);

    // Regla 3: se despeja avg_span de span_factor = 1 + (avg_span - 18) / 60
    const actualHoldFactor =
      chosen.reduce((acc, h) => acc + h.difficultyRatingWeight, 0) / chosen.length;
    const neededSpanFactor = clamp(
      target.weightFactor / (actualHoldFactor * inclineFactor),
      DIFFICULTY_CONSTANTS.SPAN_MIN,
      DIFFICULTY_CONSTANTS.SPAN_MAX,
    );
    const targetSpan =
      DIFFICULTY_CONSTANTS.COMFORTABLE_SPAN +
      (neededSpanFactor - 1) * DIFFICULTY_CONSTANTS.SPAN_DIVISOR;

    // Regla 4
    const placedHolds = this.layout(chosen, targetSpan);

    const { grade, breakdown } = this.difficulty.calculate(
      placedHolds.map((p) => {
        const hold = chosen.find((h) => h.id === p.holdId)!;
        return {
          xPercent: p.xPercent,
          yPercent: p.yPercent,
          role: p.role,
          difficultyRatingWeight: hold.difficultyRatingWeight,
        };
      }),
      request.wallInclineDeg,
      scale,
    );

    return {
      placedHolds,
      estimatedGradeId: grade?.id ?? target.id,
      rationale: this.explain(target.levelLabel, grade?.levelLabel, chosen.length, breakdown),
    };
  }

  /** Toma las `count` presas cuyo peso está más cerca del exigido por el grado. */
  private pickHolds(available: HoldDTO[], count: number, desiredWeight: number): HoldDTO[] {
    const hands = available.filter((h) => h.typeCategory !== 'foothold');
    const pool = hands.length >= count ? hands : available;

    return [...pool]
      .sort(
        (a, b) =>
          Math.abs(a.difficultyRatingWeight - desiredWeight) -
          Math.abs(b.difficultyRatingWeight - desiredWeight),
      )
      .slice(0, count);
  }

  /**
   * Reparte las presas de abajo (y=92%) hacia arriba (y=8%) en zigzag, con la
   * amplitud horizontal justa para que la distancia entre presas consecutivas
   * sea `targetSpan`.
   */
  private layout(holds: HoldDTO[], targetSpan: number): PlacedHoldDTO[] {
    const Y_BOTTOM = 92;
    const Y_TOP = 8;
    const n = holds.length;
    const dy = n > 1 ? (Y_BOTTOM - Y_TOP) / (n - 1) : 0;

    // dist = hypot(dx, dy) = targetSpan  ->  dx = sqrt(span^2 - dy^2)
    const dx = Math.sqrt(Math.max(targetSpan * targetSpan - dy * dy, 0));
    const amplitude = clamp(dx / 2, 0, 42);

    return holds.map((hold, i) => {
      const yPercent = Number((Y_BOTTOM - dy * i).toFixed(2));
      const xPercent = Number(clamp(50 + (i % 2 === 0 ? -amplitude : amplitude), 6, 94).toFixed(2));
      return {
        holdId: hold.id,
        xPercent,
        yPercent,
        rotationDeg: 0,
        role: GeneratorService.roleFor(hold, i, n),
      };
    });
  }

  private static roleFor(hold: HoldDTO, index: number, total: number): HoldRoleEnum {
    if (hold.typeCategory === 'foothold') return 'foot_only';
    if (index === total - 1) return 'top';
    if (index === 0 || (total > 4 && index === 1)) return 'start';
    return 'hand';
  }

  /** RF-4.2: la propuesta se explica, no se impone. */
  private explain(
    targetLabel: string,
    estimatedLabel: string | undefined,
    holdCount: number,
    breakdown: { avgSpan: number; inclineFactor: number; holdFactor: number; score: number },
  ): string {
    const parts = [
      `Propuesta de ${holdCount} presas para ${targetLabel}.`,
      `Peso medio de agarre ${breakdown.holdFactor.toFixed(2)}, ` +
        `factor de inclinación ${breakdown.inclineFactor.toFixed(2)}, ` +
        `separación media ${breakdown.avgSpan.toFixed(1)}%.`,
      `Índice compuesto ${breakdown.score.toFixed(2)}`,
      estimatedLabel
        ? `-> se estima ${estimatedLabel}${estimatedLabel === targetLabel ? ' (coincide con el objetivo).' : `, un escalón respecto al objetivo ${targetLabel}.`}`
        : '.',
      'Arrastra, gira y reasigna funciones antes de publicar: el grado final lo decides tú.',
    ];
    return parts.join(' ');
  }
}
