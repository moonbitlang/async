///|
async test "single-frame unmasked text message" {
  @async.with_task_group(group => {
    let frame = b"\x81\x05\x48\x65\x6c\x6c\x6f"
    let (reader, writer) = @pipe.pipe()
    group.spawn_bg(() => {
        defer writer.close()
        writer.write(frame)
      })
    let data = Frame::read(reader)
    inspect(
      data.data,
      content=(
        #|b"\x48\x65\x6c\x6c\x6f"
      ),
    )
  })
}

///|
async test "single-frame masked text message" {
  @async.with_task_group(group => {
    let frame = b"\x81\x85\x37\xfa\x21\x3d\x7f\x9f\x4d\x51\x58"
    let (reader, writer) = @pipe.pipe()
    defer reader.close()
    group.spawn_bg(() => {
        defer writer.close()
        writer.write(frame)
      })
    let data = Frame::read(reader)
    inspect(
      data.data,
      content=(
        #|b"\x48\x65\x6c\x6c\x6f"
      ),
    )
  })
}

///|
async test "fragmented unmasked text message" {
  @async.with_task_group(group => {
    let frame1 = b"\x01\x03\x48\x65\x6c"
    let frame2 = b"\x80\x02\x6c\x6f"
    let (reader, writer) = @pipe.pipe()
    defer reader.close()
    group.spawn_bg(() => {
        defer writer.close()
        writer.write(frame1)
        writer.write(frame2)
      })
    let data1 = Frame::read(reader)
    inspect(
      data1.data,
      content=(
        #|b"\x48\x65\x6c"
      ),
    )
    let data2 = Frame::read(reader)
    inspect(
      data2.data,
      content=(
        #|b"\x6c\x6f"
      ),
    )
  })
}
