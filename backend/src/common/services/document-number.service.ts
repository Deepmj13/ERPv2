import { Injectable } from '@nestjs/common';

@Injectable()
export class DocumentNumberService {
  async next(
    prefix: string,
    organizationId: string,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    tx: any,
  ): Promise<string> {
    const year = new Date().getFullYear();
    const seq = await tx.docNumberSequence.upsert({
      where: {
        organizationId_prefix_year: { organizationId, prefix, year },
      },
      create: { organizationId, prefix, year, lastValue: 1 },
      update: { lastValue: { increment: 1 } },
    });
    return `${prefix}-${year}-${String(seq.lastValue).padStart(5, '0')}`;
  }
}