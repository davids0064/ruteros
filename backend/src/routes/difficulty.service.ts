import { Injectable } from '@nestjs/common';
import type { GradeValueDTO } from '../grades/dto/grade.dto';
import type { HoldRoleEnum } from '../database/schema';

/** Entrada mínima del motor: una presa colocada con su peso intrínseco. */
export interface WeightedPlacement {
  xPercent: number;
  yPercent: number;
  role: HoldRoleEnum;
  difficultyRatingWeight: number;
}

export interface DifficultyBreakdown {
  holdFactor: number;
  inclineFactor: number;
  spanFactor: number;
  avgSpan: number;
  score: number;
}

/**
 * Constantes calibrables (04 §6): "no son verdades del dominio".
 * Se exponen para poder ajustarlas sin tocar el algoritmo.
 */
export const DIFFICULTY_CONSTANTS = {
  /** Peso del desplome en `incline_factor`. */
  INCLINE_WEIGHT: 0.8,
  /** Separación cómoda de referencia, en % de la diagonal del muro. */
  COMFORTABLE_SPAN: 18,
  /** Divisor de la desviación de separación. */
  SPAN_DIVISOR: 60,
  SPAN_MIN: 0.75,
  SPAN_MAX: 1.6,
};

const clamp = (v: number, min: number, max: number) => Math.min(Math.max(v, min), max);

/**
 * Motor de dificultad — 04_COMPONENT_SPECS.md §6.
 *
 * El resultado es una SUGERENCIA para `calculated_grade_id`. `target_grade_id`,
 * elección del setter, nunca se sobrescribe: es la mitad humana del
 * human-in-the-loop.
 */
@Injectable()
export class DifficultyService {
  /** Paso 1-4: índice compuesto. */
  score(placements: WeightedPlacement[], wallInclineDeg: number): DifficultyBreakdown {
    // Paso 1: se excluyen los pies — no aportan a la dificultad de agarre.
    const hands = placements.filter((p) => p.role !== 'foot_only');

    const holdFactor =
      hands.length > 0
        ? hands.reduce((acc, p) => acc + p.difficultyRatingWeight, 0) / hands.length
        : 1;

    // Paso 2: desplome = theta positivo.
    const inclineFactor =
      1 + (Math.max(wallInclineDeg, 0) / 90) * DIFFICULTY_CONSTANTS.INCLINE_WEIGHT;

    // Paso 3: de abajo hacia arriba = y_percent descendente.
    const ordered = [...hands].sort((a, b) => b.yPercent - a.yPercent);
    let avgSpan = DIFFICULTY_CONSTANTS.COMFORTABLE_SPAN;
    if (ordered.length >= 2) {
      let total = 0;
      for (let i = 0; i < ordered.length - 1; i += 1) {
        total += Math.hypot(
          ordered[i + 1].xPercent - ordered[i].xPercent,
          ordered[i + 1].yPercent - ordered[i].yPercent,
        );
      }
      avgSpan = total / (ordered.length - 1);
    }

    const spanFactor = clamp(
      1 + (avgSpan - DIFFICULTY_CONSTANTS.COMFORTABLE_SPAN) / DIFFICULTY_CONSTANTS.SPAN_DIVISOR,
      DIFFICULTY_CONSTANTS.SPAN_MIN,
      DIFFICULTY_CONSTANTS.SPAN_MAX,
    );

    // Paso 4
    return {
      holdFactor,
      inclineFactor,
      spanFactor,
      avgSpan,
      score: holdFactor * inclineFactor * spanFactor,
    };
  }

  /**
   * Paso 5: el `grade_value` cuyo `weight_factor` es el más cercano a `score`.
   * Empate -> el `rank_ordinal` menor.
   */
  mapToScale(score: number, scale: GradeValueDTO[]): GradeValueDTO | null {
    if (scale.length === 0) return null;

    return scale.reduce((best, candidate) => {
      const dBest = Math.abs(best.weightFactor - score);
      const dCand = Math.abs(candidate.weightFactor - score);
      if (dCand < dBest) return candidate;
      if (dCand === dBest && candidate.rankOrdinal < best.rankOrdinal) return candidate;
      return best;
    });
  }

  calculate(
    placements: WeightedPlacement[],
    wallInclineDeg: number,
    scale: GradeValueDTO[],
  ): { grade: GradeValueDTO | null; breakdown: DifficultyBreakdown } {
    const breakdown = this.score(placements, wallInclineDeg);
    return { grade: this.mapToScale(breakdown.score, scale), breakdown };
  }
}
