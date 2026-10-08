import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/data/repositories/conversation/image_context_tracker.dart';
import 'package:litert_hackathon/domain/models/assistant_event.dart';

void main() {
  late ImageContextTracker images;
  final cats = Uint8List.fromList([1, 2, 3]);
  // Equal bytes, another object: a new image.
  final catsCopy = Uint8List.fromList([1, 2, 3]);
  final dogs = Uint8List.fromList([4, 5, 6]);

  setUp(() => images = ImageContextTracker());

  test('nothing is in context at first; an attached image is sent, nothing '
      'attached sends nothing', () {
    expect(images.inContext, isNull);
    expect(images.toSend(cats), same(cats));
    expect(images.toSend(null), isNull);
    expect(images.resendReason(cats), isNull, reason: 'never lost');
  });

  test('a normal end makes the sent image the one in context: the same '
      'object is not sent again, an equal copy is', () {
    images.settle(stopped: false, sentImage: cats);

    expect(images.inContext, same(cats));
    expect(images.toSend(cats), isNull);
    expect(images.toSend(catsCopy), same(catsCopy));
    expect(images.toSend(null), isNull);
  });

  test('a normal end without a sent image keeps the image in context', () {
    images.settle(stopped: false, sentImage: cats);

    images.settle(stopped: false, sentImage: null);

    expect(images.inContext, same(cats));
  });

  test('a stop loses the image in context; re-sending it says why', () {
    images.settle(stopped: false, sentImage: cats);

    images.settle(stopped: true, sentImage: null);

    expect(images.inContext, isNull);
    expect(images.toSend(cats), same(cats));
    expect(images.resendReason(cats), ImageLoss.stop);
    expect(images.resendReason(catsCopy), isNull, reason: 'another object');
  });

  test('a stop in the turn that first sent an image loses that image', () {
    images.settle(stopped: true, sentImage: cats);

    expect(images.inContext, isNull);
    expect(images.resendReason(cats), ImageLoss.stop);
  });

  test('the image a turn sent supersedes the one in context when it is '
      'lost', () {
    images.settle(stopped: false, sentImage: cats);

    images.lose(ImageLoss.failure, sentImage: dogs);

    expect(images.inContext, isNull);
    expect(images.resendReason(dogs), ImageLoss.failure);
    expect(images.resendReason(cats), isNull);
  });

  test('each loss reason is kept until the next loss or a normal end', () {
    for (final reason in ImageLoss.values) {
      images
        ..settle(stopped: false, sentImage: cats)
        ..lose(reason);
      expect(images.resendReason(cats), reason);
    }

    images.settle(stopped: false, sentImage: cats);
    expect(images.resendReason(cats), isNull, reason: 'back in context');
  });

  test('a loss with nothing in context keeps the earlier lost image and '
      'its reason', () {
    images
      ..settle(stopped: false, sentImage: cats)
      ..lose(ImageLoss.stop)
      ..lose(ImageLoss.reset);

    expect(images.resendReason(cats), ImageLoss.stop);
  });
}
