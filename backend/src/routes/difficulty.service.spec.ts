import { DIFFICULTY_CONSTANTS, DifficultyService, type WeightedPlacement } from './difficulty.service';
import type { GradeValueDTO } from '../grades/dto/grade.dto';

const grade = (id: string, label: string, rank: number, weight: number): GradeValueDTO => ({
  id,
  systemId: 'sys',
  levelLabel: label,
  rankOrdinal: rank,
  weightFactor: weight,
});

/** Extracto de la Matriz Referencial de 01_PRD.md §7. */
const V_SCALE = [
  grade('v0', 'V0', 0, 1.0),
  grade('v4', 'V4', 4, 2.5),
  grade('v8', 'V8', 8, 4.8),
];

const place = (
  xPercent: number,
  yPercent: number,
  weight: number,
  role: WeightedPlacement['role'] = 'hand',
): WeightedPlacement => ({ xPercent, yPercent, role, difficultyRatingWeight: weight });

describe('DifficultyService (04 §6)', () => {
  const service = new DifficultyService();

  describe('paso 1 — dificultad intrínseca de agarres', () => {
    it('promedia el peso de las presas', () => {
      const { holdFactor } = service.score([place(50, 90, 1), place(50, 72, 3)], 0);
      expect(holdFactor).toBe(2);
    });

    it('excluye las presas de pie del promedio', () => {
      const { holdFactor } = service.score(
        [place(50, 90, 1), place(50, 72, 3), place(20, 80, 9, 'foot_only')],
        0,
      );
      expect(holdFactor).toBe(2);
    });

    it('cae a 1 cuando el bloque es sólo de pies', () => {
      expect(service.score([place(20, 80, 9, 'foot_only')], 0).holdFactor).toBe(1);
    });
  });

  describe('paso 2 — penalización por inclinación', () => {
    it('vale 1 en placa vertical', () => {
      expect(service.score([place(50, 90, 1)], 0).inclineFactor).toBe(1);
    });

    it('vale 1.8 a 90° de desplome', () => {
      expect(service.score([place(50, 90, 1)], 90).inclineFactor).toBeCloseTo(1.8, 10);
    });

    it('ignora las placas tumbadas: theta negativo no bonifica', () => {
      expect(service.score([place(50, 90, 1)], -40).inclineFactor).toBe(1);
    });
  });

  describe('paso 3 — factor de separación', () => {
    it('vale 1 cuando la separación media es la cómoda (18%)', () => {
      const { spanFactor, avgSpan } = service.score(
        [place(50, 90, 1), place(50, 72, 1)],
        0,
      );
      expect(avgSpan).toBeCloseTo(DIFFICULTY_CONSTANTS.COMFORTABLE_SPAN, 10);
      expect(spanFactor).toBeCloseTo(1, 10);
    });

    it('ordena de abajo hacia arriba (y_percent descendente)', () => {
      const ascendente = service.score([place(50, 90, 1), place(50, 60, 1), place(50, 30, 1)], 0);
      const desordenado = service.score([place(50, 60, 1), place(50, 30, 1), place(50, 90, 1)], 0);
      expect(desordenado.avgSpan).toBeCloseTo(ascendente.avgSpan, 10);
      expect(ascendente.avgSpan).toBeCloseTo(30, 10);
    });

    it('se satura en los extremos [0.75, 1.6]', () => {
      const juntas = service.score([place(50, 90, 1), place(50, 89, 1)], 0);
      expect(juntas.spanFactor).toBe(DIFFICULTY_CONSTANTS.SPAN_MIN);

      const lejanas = service.score([place(5, 95, 1), place(95, 5, 1)], 0);
      expect(lejanas.spanFactor).toBe(DIFFICULTY_CONSTANTS.SPAN_MAX);
    });

    it('vale 1 con una sola presa de mano: no hay distancia que medir', () => {
      expect(service.score([place(50, 90, 1)], 0).spanFactor).toBeCloseTo(1, 10);
    });
  });

  describe('paso 4 — índice compuesto', () => {
    it('es el producto de los tres factores', () => {
      const b = service.score([place(50, 90, 2), place(50, 72, 2)], 45);
      expect(b.score).toBeCloseTo(b.holdFactor * b.inclineFactor * b.spanFactor, 10);
    });
  });

  describe('paso 5 — mapeo a la escala', () => {
    it('elige el weight_factor más cercano', () => {
      expect(service.mapToScale(2.4, V_SCALE)?.levelLabel).toBe('V4');
      expect(service.mapToScale(1.1, V_SCALE)?.levelLabel).toBe('V0');
      expect(service.mapToScale(9.9, V_SCALE)?.levelLabel).toBe('V8');
    });

    it('ante un empate se queda con el rank_ordinal menor', () => {
      const escala = [grade('a', 'A', 5, 1.0), grade('b', 'B', 2, 3.0)];
      expect(service.mapToScale(2.0, escala)?.levelLabel).toBe('B');
    });

    it('devuelve null si la escala está vacía', () => {
      expect(service.mapToScale(2.5, [])).toBeNull();
    });
  });

  describe('contrato', () => {
    it('un bloque de regletas duras en desplome puntúa por encima de uno de jugs en placa', () => {
      const jugsEnPlaca = service.calculate(
        [place(50, 90, 1), place(50, 72, 1)],
        0,
        V_SCALE,
      );
      const regletasEnDesplome = service.calculate(
        [place(30, 90, 4.5), place(70, 60, 4.5)],
        40,
        V_SCALE,
      );
      expect(regletasEnDesplome.breakdown.score).toBeGreaterThan(jugsEnPlaca.breakdown.score);
      expect(regletasEnDesplome.grade?.rankOrdinal).toBeGreaterThan(
        jugsEnPlaca.grade!.rankOrdinal,
      );
    });
  });
});
